# Third-party software

This project is licensed under the GNU General Public License v3.0 (see `LICENSE`).
The release zips bundle the following components:

| Component | License | Source |
|---|---|---|
| UndertaleModLib (from UndertaleModTool), linked by the patcher | GPL-3.0 | https://github.com/UnderminersTeam/UndertaleModTool |
| Underanalyzer (GML decompiler/compiler used by UndertaleModLib), incl. `GameSpecificData/` | MPL-2.0 | https://github.com/UnderminersTeam/Underanalyzer |
| Magick.NET (image library used by UndertaleModLib) | Apache-2.0 | https://github.com/dlemstra/Magick.NET |
| .NET runtime and libraries (self-contained runtime in the zips) | MIT | https://github.com/dotnet/runtime |

Source for the GPL components is available at the links above. The patcher source is in `patcher/`;
it builds against UndertaleModLib.

DELTARUNE and its game files belong to Toby Fox and are not included or covered by this license.
