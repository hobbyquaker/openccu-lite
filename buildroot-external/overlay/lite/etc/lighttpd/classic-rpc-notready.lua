-- openccu-lite: a classic RPC socket answers 503 until the boot is finished, as upstream's
-- webui_remoteapi_notready.conf does (its notready.cgi is not on lite), and passes the request on
-- to its backend (proxy.server in the same block) once /var/status/startupFinished exists.
--
-- The check is made per request, not by the configuration: upstream switches the sockets from
-- not-ready to ready with a lighttpd reload at the end of the boot, and that graceful restart cut
-- every long-lived connection lighttpd held - an addon's event stream among them. With the check
-- here the configuration is the same before and after, and the end of the boot reloads nothing.
local stat = (lighty.c and lighty.c.stat) or lighty.stat
if stat("/var/status/startupFinished") then
    return 0
end
return 503
