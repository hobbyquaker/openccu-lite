-- openccu-lite: no request reaches a backend with a client-sent X-Occulite-Session, nor with a
-- client-sent X-Forwarded-For, X-Forwarded-Proto, X-Forwarded-Host or Forwarded.
--
-- occulited's session gate (/etc/lighttpd/occulite-gate.lua, from package/occulited) hands an addon
-- the id of the session it validated in the request header X-Occulite-Session, and removes a
-- client-sent one first. The gate runs only in front of /addons/. This script runs for every other
-- request, on every socket (modules.conf sets it globally, and the gate's own block replaces it):
-- an addon's drop-in may proxy a path outside /addons/ (RedMatic's /description.xml and
-- /api/*/lights to Node-RED's Amazon Echo hub) or open a socket of its own, and none of those may
-- see a header that looks like the gate's. The header is therefore present only behind a session
-- the gate validated.
--
-- The forwarding headers: lighttpd's mod_proxy appends the client's address to an
-- X-Forwarded-For the client sent instead of replacing it, so a backend that reads the header
-- would take the client's word for its address - a token's address restriction, the lockout by
-- address and the loopback-only routes all hang on it. With the client's copy gone, the only
-- element is the one lighttpd writes. It appends to a client's Forwarded the same way
-- (proxy.forwarded), and sets X-Forwarded-Proto and X-Forwarded-Host itself over the client's; all
-- four go here, so what a backend receives is lighttpd's alone. occulited trusts only the last
-- element of X-Forwarded-For in any case; this is the second half, for every backend behind
-- lighttpd.
--
-- The rule is the gate's, and the two are kept in step: every request header whose name a CGI
-- reads as one of these variables - any case, any character that is not a letter or a digit in
-- place of the dashes (mod_cgi turns those into "_") - is removed. lighttpd keeps a removed header
-- as an empty entry and forwards no empty header; a header that still has a value afterwards fails
-- the request closed.
--
-- Needs lighttpd 1.4.60 or later (lighty.r), like the gate.
local r = lighty.r
if r == nil then
    return 500
end

local STRIPPED = {
    X_OCCULITE_SESSION = true,
    X_FORWARDED_FOR = true,
    X_FORWARDED_PROTO = true,
    X_FORWARDED_HOST = true,
    FORWARDED = true,
}
local function is_stripped(name)
    return STRIPPED[(name:upper():gsub("[^%w]", "_"))] == true
end

local names = {}
for k in pairs(r.req_header) do
    if is_stripped(k) then names[#names + 1] = k end
end
if #names == 0 then
    return 0
end
for _, k in ipairs(names) do
    r.req_header[k] = nil
end
for k, v in pairs(r.req_header) do
    if is_stripped(k) and v ~= nil and v ~= "" then
        r.resp_header["Content-Type"] = "application/json"
        r.resp_body:set({ '{"error":"session-header","message":"a client-sent session or forwarding header could not be removed"}' })
        return 500
    end
end
return 0
