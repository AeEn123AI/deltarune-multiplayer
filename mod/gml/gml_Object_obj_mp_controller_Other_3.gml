// Game End: close sockets cleanly.
if (variable_global_exists("mp_inited"))
    mp_disconnect("");
