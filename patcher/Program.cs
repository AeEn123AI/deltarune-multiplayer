// Deltarune Multiplayer patcher.
// Applies the GML sources and hook files of the mod to a chapter's data.win.
//
//   drm-patcher <input data.win> <output data.win> <mod dir> <chapter number>
//
// <mod dir>/gml/*.gml        new code entries (scripts / object events), created if missing
// <mod dir>/hooks/*.hook     edits to existing code entries (see ParseHooks)
using System.Text;
using UndertaleModLib;
using UndertaleModLib.Compiler;
using UndertaleModLib.Models;

static class Program
{
    record Hook(string Kind, string Entry, string Text, string With, bool Optional, string Source);

    static int Main(string[] args)
    {
        if (args.Length >= 1 && (args[0] == "install" || args[0] == "uninstall"))
            return InstallMain(args);
        if (args.Length == 3 && args[0] == "--names")
        {
            using var f = File.OpenRead(args[1]);
            var d = UndertaleIO.Read(f, (w, _) => { }, _ => { });
            IEnumerable<string> names = args[2] switch
            {
                "sprites" => d.Sprites.Select(x => x.Name.Content),
                "objects" => d.GameObjects.Select(x => x.Name.Content + (x.ParentId != null ? " : " + x.ParentId.Name.Content : "")),
                "rooms" => d.Rooms.Select(x => x.Name.Content),
                "sounds" => d.Sounds.Select(x => x.Name.Content),
                "fonts" => d.Fonts.Select(x => x.Name.Content + " " + x.EmSize),
                _ => d.Code.Select(x => x.Name.Content),
            };
            foreach (var n in names) Console.WriteLine(n);
            return 0;
        }
        if (args.Length == 3 && args[0] == "--find-object")
        {
            using var f = File.OpenRead(args[1]);
            var d = UndertaleIO.Read(f, (w, _) => { }, _ => { });
            foreach (var r in d.Rooms)
                foreach (var layer in r.Layers ?? new())
                    if (layer.InstancesData != null)
                        foreach (var inst in layer.InstancesData.Instances)
                            if (inst.ObjectDefinition?.Name.Content == args[2])
                                Console.WriteLine($"{r.Name.Content} {inst.X},{inst.Y}");
            return 0;
        }
        if (args.Length == 2 && args[0] == "--room-objects")
        {
            // Every (room, object) pair, once each: "room object x,y" (first instance).
            using var f = File.OpenRead(args[1]);
            var d = UndertaleIO.Read(f, (w, _) => { }, _ => { });
            foreach (var r in d.Rooms)
            {
                var seen = new HashSet<string>();
                foreach (var layer in r.Layers ?? new())
                    if (layer.InstancesData != null)
                        foreach (var inst in layer.InstancesData.Instances)
                        {
                            var n = inst.ObjectDefinition?.Name.Content;
                            if (n != null && seen.Add(n))
                                Console.WriteLine($"{r.Name.Content} {n} {inst.X},{inst.Y}");
                        }
            }
            return 0;
        }
        if (args.Length >= 3 && args[0] == "--decompile")
        {
            using var f = File.OpenRead(args[1]);
            var d = UndertaleIO.Read(f, (w, _) => { }, _ => { });
            foreach (var n in args.Skip(2))
            {
                Console.WriteLine("// ===== " + n);
                var c = d.Code.ByName(n);
                Console.WriteLine(c == null ? "// (missing)" : Decompile(d, c));
            }
            return 0;
        }
        if (args.Length < 4)
        {
            Console.Error.WriteLine("usage: drm-patcher <in data.win> <out data.win> <mod dir> <chapter>");
            return 2;
        }
        return Patch(args[0], args[1], args[2], int.Parse(args[3]));
    }

    // install [DELTARUNE folder] [--mod <dir>] : patches every chapter found, keeping
    // the original as data.win.vanilla (always patching from that pristine copy).
    // uninstall [DELTARUNE folder] : restores the originals.
    static int InstallMain(string[] args)
    {
        bool install = args[0] == "install";
        string game = args.Length > 1 && !args[1].StartsWith("--") ? args[1] : Directory.GetCurrentDirectory();
        string modDir = Path.Combine(AppContext.BaseDirectory, "mod");
        int mi = Array.IndexOf(args, "--mod");
        if (mi >= 0 && mi + 1 < args.Length) modDir = args[mi + 1];
        if (!File.Exists(Path.Combine(game, "DELTARUNE.exe")) && !Directory.Exists(Path.Combine(game, "chapter1_windows")))
        {
            Console.Error.WriteLine($"'{game}' doesn't look like a DELTARUNE folder (expected chapterN_windows folders).");
            Console.Error.WriteLine("Usage: drm-patcher install \"C:\\...\\DELTARUNE\"");
            return 2;
        }
        if (install && !Directory.Exists(Path.Combine(modDir, "gml")))
        {
            Console.Error.WriteLine($"Mod files not found in '{modDir}'.");
            return 2;
        }
        int ok = 0, failed = 0;
        for (int ch = 1; ch <= 9; ch++)
        {
            string dir = Path.Combine(game, $"chapter{ch}_windows");
            string win = Path.Combine(dir, "data.win");
            string vanilla = win + ".vanilla";
            if (!File.Exists(win) && !File.Exists(vanilla)) continue;
            if (!install)
            {
                if (File.Exists(vanilla)) { File.Copy(vanilla, win, true); File.Delete(vanilla); Console.WriteLine($"Chapter {ch}: restored."); }
                continue;
            }
            Console.WriteLine($"=== Chapter {ch}");
            if (!File.Exists(vanilla)) File.Copy(win, vanilla);
            int r;
            try { r = Patch(vanilla, win, modDir, ch); }
            catch (Exception e) { Console.Error.WriteLine("ERROR: " + e.Message); r = 1; }
            if (r == 0) ok++;
            else
            {
                failed++;
                File.Copy(vanilla, win, true);
                Console.Error.WriteLine($"Chapter {ch}: patch failed, left unmodified.");
            }
        }
        if (install) Console.WriteLine($"\nDone: {ok} chapter(s) patched, {failed} failed. Press F9 in game to open the multiplayer menu.");
        return failed > 0 ? 1 : 0;
    }

    static int Patch(string inPath, string outPath, string modDir, int chapter)
    {
        Console.WriteLine($"Loading {inPath} ...");
        UndertaleData data;
        using (var fs = File.OpenRead(inPath))
            data = UndertaleIO.Read(fs, (w, _) => Console.WriteLine("  warn: " + w), _ => { });

        var group = new CodeImportGroup(data) { ThrowOnNoOpFindReplace = true };
        int count = 0;

        // 1. New/replaced code entries.
        foreach (var file in Directory.GetFiles(Path.Combine(modDir, "gml"), "*.gml").OrderBy(f => f))
        {
            string text = File.ReadAllText(file);
            if (!ChapterAllowed(text, chapter)) continue;
            text = Preprocess(text, chapter);
            group.QueueReplace(Path.GetFileNameWithoutExtension(file), text);
            count++;
        }
        // Chapter-specific overrides: gml/chN/*.gml
        string chDir = Path.Combine(modDir, "gml", "ch" + chapter);
        if (Directory.Exists(chDir))
            foreach (var file in Directory.GetFiles(chDir, "*.gml").OrderBy(f => f))
            {
                group.QueueReplace(Path.GetFileNameWithoutExtension(file), Preprocess(File.ReadAllText(file), chapter));
                count++;
            }

        // 2. Hooks into existing code.
        var hooks = new List<Hook>();
        foreach (var file in Directory.GetFiles(Path.Combine(modDir, "hooks"), "*.hook").OrderBy(f => f))
            hooks.AddRange(ParseHooks(file, chapter));
        foreach (var h in hooks)
        {
            var code = data.Code.ByName(h.Entry);
            if (code == null)
            {
                if (h.Optional) { Console.WriteLine($"  skip (missing entry) {h.Entry} [{h.Source}]"); continue; }
                Console.Error.WriteLine($"ERROR: code entry {h.Entry} not found [{h.Source}]");
                return 1;
            }
            if (h.Kind == "find" && h.Optional)
            {
                // Optional find: only queue if the text exists in the current decompilation.
                string dec = Decompile(data, code);
                if (!TrimmedContains(dec, h.Text)) { Console.WriteLine($"  skip (no match) {h.Entry} [{h.Source}]"); continue; }
            }
            switch (h.Kind)
            {
                case "append": group.QueueAppend(code, h.Text); break;
                case "prepend": group.QueuePrepend(code, h.Text); break;
                case "replace": group.QueueReplace(code, h.Text); break;
                case "find": group.QueueTrimmedLinesFindReplace(code, h.Text, h.With); break;
                case "regex": group.QueueRegexFindReplace(code, h.Text, h.With); break;
            }
            count++;
        }

        // Catch references to assets this chapter doesn't have: GML would silently treat
        // them as (unset) variables and crash at runtime.
        var known = new HashSet<string>();
        foreach (var o in data.GameObjects) known.Add(o.Name.Content);
        foreach (var o in data.Sprites) known.Add(o.Name.Content);
        foreach (var o in data.Sounds) known.Add(o.Name.Content);
        foreach (var o in data.Rooms) known.Add(o.Name.Content);
        foreach (var o in data.Fonts) known.Add(o.Name.Content);
        foreach (var o in data.Scripts) known.Add(o.Name.Content);
        foreach (var o in data.Functions) known.Add(o.Name.Content);
        var modFiles = Directory.GetFiles(Path.Combine(modDir, "gml"), "*.gml", SearchOption.AllDirectories)
            .Where(f => Path.GetDirectoryName(f) == Path.Combine(modDir, "gml") || Path.GetFileName(Path.GetDirectoryName(f)) == "ch" + chapter)
            .Concat(Directory.GetFiles(Path.Combine(modDir, "hooks"), "*.hook"));
        var missing = new List<string>();
        foreach (var f in modFiles)
        {
            string t = File.ReadAllText(f);
            if (f.EndsWith(".gml") && !ChapterAllowed(t, chapter)) continue;
            t = System.Text.RegularExpressions.Regex.Replace(t, @"//[^\n]*|^;;[^\n]*", "", System.Text.RegularExpressions.RegexOptions.Multiline);
            foreach (System.Text.RegularExpressions.Match m in System.Text.RegularExpressions.Regex.Matches(t, @"(?<![\w""])((?:obj|spr|snd|scr|room|fnt)_[A-Za-z0-9_]+)"))
            {
                var name = m.Groups[1].Value;
                if (name.StartsWith("obj_mp_") || name.StartsWith("scr_mp_") || known.Contains(name)) continue;
                if (name.StartsWith("room_") && t.Length > m.Index + m.Length && t[m.Index + m.Length] == '(') continue; // builtin room_* functions
                missing.Add($"{Path.GetFileName(f)}: {name}");
            }
        }
        if (missing.Count > 0)
        {
            Console.Error.WriteLine("ERROR: mod references assets missing from chapter " + chapter + ":");
            foreach (var m in missing.Distinct()) Console.Error.WriteLine("  " + m);
            return 1;
        }

        Console.WriteLine($"Compiling {count} operations ...");
        CompileResult result;
        try { result = group.Import(false); }
        catch (Exception e) { Console.Error.WriteLine("ERROR: " + e.Message); return 1; }
        if (!result.Successful)
        {
            Console.Error.WriteLine("Compile errors:");
            Console.Error.WriteLine(result.PrintAllErrors(false));
            return 1;
        }

        // Object properties for objects created by the mod.
        var props = Path.Combine(modDir, "objects.txt");
        if (File.Exists(props)) ApplyObjectProps(data, props);

        Console.WriteLine($"Writing {outPath} ...");
        string tmp = outPath + ".tmp";
        using (var fs = File.Create(tmp))
            UndertaleIO.Write(fs, data);
        File.Move(tmp, outPath, true);
        Console.WriteLine("Done.");
        return 0;
    }

    // "// @chapters 1,2" on the first line restricts a file to those chapters.
    static bool ChapterAllowed(string text, int chapter)
    {
        var first = text.Split('\n')[0].Trim();
        if (!first.StartsWith("// @chapters")) return true;
        return first.Substring(12).Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .Select(int.Parse).Contains(chapter);
    }

    static string Preprocess(string text, int chapter) => text.Replace("__CHAPTER__", chapter.ToString());

    static string Decompile(UndertaleData data, UndertaleCode code)
    {
        var ctx = new Underanalyzer.Decompiler.DecompileContext(new UndertaleModLib.Decompiler.GlobalDecompileContext(data), code, data.ToolInfo.DecompilerSettings);
        return ctx.DecompileToString();
    }

    static bool TrimmedContains(string hay, string needle)
    {
        string norm(string s) => string.Join("\n", s.Replace("\r", "").Split('\n').Select(l => l.Trim()).Where(l => l.Length > 0));
        return norm(hay).Contains(norm(needle));
    }

    // Hook file format:
    //   #chapters 1,2         restricts following hooks (until next #chapters; "#chapters all" resets)
    //   @append <entry>       body = following lines until next directive
    //   @prepend <entry>
    //   @replace <entry>
    //   @find <entry>         search text, then "@with", replacement, then "@end"
    //   @find? / @append? ... optional variants (no error when the entry/text is missing)
    //   ;; comment lines (ignored) at column 0
    static IEnumerable<Hook> ParseHooks(string file, int chapter)
    {
        var lines = File.ReadAllLines(file);
        var result = new List<Hook>();
        bool allowed = true;
        int i = 0;
        while (i < lines.Length)
        {
            string line = lines[i];
            if (line.StartsWith("#chapters"))
            {
                var spec = line.Substring(9).Trim();
                allowed = spec == "all" || spec.Split(',', StringSplitOptions.TrimEntries).Select(int.Parse).Contains(chapter);
                i++; continue;
            }
            if (!line.StartsWith("@")) { i++; continue; }
            var parts = line.Substring(1).Split(' ', 2, StringSplitOptions.TrimEntries);
            string kind = parts[0]; bool optional = kind.EndsWith("?"); kind = kind.TrimEnd('?');
            string entry = parts.Length > 1 ? parts[1] : "";
            string src = $"{Path.GetFileName(file)}:{i + 1}";
            i++;
            var body = new StringBuilder(); var with = new StringBuilder();
            if (kind == "find" || kind == "regex")
            {
                while (i < lines.Length && lines[i] != "@with") body.AppendLine(lines[i++]);
                i++;
                while (i < lines.Length && lines[i] != "@end") with.AppendLine(lines[i++]);
                i++;
            }
            else
            {
                while (i < lines.Length && !lines[i].StartsWith("@") && !lines[i].StartsWith("#chapters"))
                {
                    if (!lines[i].StartsWith(";;")) body.AppendLine(lines[i]);
                    i++;
                }
            }
            if (allowed)
                result.Add(new Hook(kind, entry, Preprocess(body.ToString().TrimEnd(), chapter), Preprocess(with.ToString().TrimEnd(), chapter), optional, src));
        }
        return result;
    }

    // objects.txt lines: <object> persistent=1 visible=1 depth=-100 parent=obj_x
    static void ApplyObjectProps(UndertaleData data, string file)
    {
        foreach (var raw in File.ReadAllLines(file))
        {
            var line = raw.Trim();
            if (line.Length == 0 || line.StartsWith(";;")) continue;
            var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            var obj = data.GameObjects.ByName(parts[0]);
            if (obj == null)
            {
                obj = new UndertaleGameObject { Name = data.Strings.MakeString(parts[0]) };
                data.GameObjects.Add(obj);
            }
            foreach (var kv in parts.Skip(1))
            {
                var p = kv.Split('=');
                switch (p[0])
                {
                    case "persistent": obj.Persistent = p[1] == "1"; break;
                    case "visible": obj.Visible = p[1] == "1"; break;
                    case "depth": obj.Depth = int.Parse(p[1]); break;
                    case "parent": obj.ParentId = data.GameObjects.ByName(p[1]); break;
                }
            }
        }
    }
}
