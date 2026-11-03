package feed

import (
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"syscall"

	"rss-server/internal/config"
)

var errPrivateAddr = errors.New("fetching private or local addresses is disabled (RSS_ALLOW_PRIVATE_FETCH)")

// reserved holds special-purpose ranges that pass IsGlobalUnicast but are not public.
var reserved = func() []netip.Prefix {
	var ps []netip.Prefix
	for _, c := range []string{
		"0.0.0.0/8", "100.64.0.0/10" /* CGNAT, also Tailscale */, "192.0.0.0/24", "192.0.2.0/24",
		"198.18.0.0/15", "198.51.100.0/24", "203.0.113.0/24", "240.0.0.0/4",
		"::/96" /* IPv4-compatible */, "64:ff9b:1::/48", "100::/64", "2001::/32" /* Teredo */, "2001:db8::/32",
	} {
		ps = append(ps, netip.MustParsePrefix(c))
	}
	return ps
}()

var (
	nat64  = netip.MustParsePrefix("64:ff9b::/96")
	sixTo4 = netip.MustParsePrefix("2002::/16")
)

// isPublic is deny-by-default: only global unicast outside reserved ranges passes.
// IPv4 embedded in NAT64 / 6to4 addresses is checked as well.
func isPublic(ip netip.Addr) bool {
	ip = ip.Unmap()
	if b := ip.As16(); nat64.Contains(ip) {
		return isPublic(netip.AddrFrom4([4]byte(b[12:16])))
	} else if sixTo4.Contains(ip) {
		return isPublic(netip.AddrFrom4([4]byte(b[2:6])))
	}
	if !ip.IsGlobalUnicast() || ip.IsPrivate() {
		return false
	}
	for _, p := range reserved {
		if p.Contains(ip) {
			return false
		}
	}
	return true
}

// newClient builds the feed HTTP client. Unless private fetches are allowed, the
// dialer rejects non-public IPs after DNS resolution (covering redirects and DNS
// rebinding) and environment proxies are ignored.
func newClient(cfg config.Config) *http.Client {
	dialer := &net.Dialer{Timeout: cfg.FetchTimeout}
	if !cfg.AllowPrivateFetch {
		dialer.Control = func(_, address string, _ syscall.RawConn) error {
			ap, err := netip.ParseAddrPort(address)
			if err != nil {
				return err
			}
			if !isPublic(ap.Addr()) {
				return errPrivateAddr
			}
			return nil
		}
	}
	tr := http.DefaultTransport.(*http.Transport).Clone()
	tr.DialContext = dialer.DialContext
	if !cfg.AllowPrivateFetch {
		// A proxy would make the dialer check the proxy's IP instead of the feed's.
		tr.Proxy = nil
	}
	return &http.Client{
		Timeout:   cfg.FetchTimeout,
		Transport: tr,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if req.URL.Scheme != "http" && req.URL.Scheme != "https" {
				return fmt.Errorf("redirect to unsupported scheme %q", req.URL.Scheme)
			}
			if len(via) >= 10 {
				return errors.New("too many redirects")
			}
			return nil
		},
	}
}

// webURL keeps only absolute http(s) links, so clients never get javascript: or data: URLs.
func webURL(raw string) string {
	u, err := url.Parse(raw)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return ""
	}
	return raw
}
