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

// cgnat is 100.64.0.0/10, also used by Tailscale; netip has no predicate for it.
var cgnat = netip.MustParsePrefix("100.64.0.0/10")

func isPrivate(ip netip.Addr) bool {
	ip = ip.Unmap()
	return ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() ||
		ip.IsInterfaceLocalMulticast() || ip.IsMulticast() || ip.IsUnspecified() || cgnat.Contains(ip)
}

// newClient builds the feed HTTP client. Unless private fetches are allowed, the
// dialer rejects non-public IPs after DNS resolution, which also covers redirects
// and DNS rebinding.
func newClient(cfg config.Config) *http.Client {
	dialer := &net.Dialer{Timeout: cfg.FetchTimeout}
	if !cfg.AllowPrivateFetch {
		dialer.Control = func(_, address string, _ syscall.RawConn) error {
			ap, err := netip.ParseAddrPort(address)
			if err != nil {
				return err
			}
			if isPrivate(ap.Addr()) {
				return errPrivateAddr
			}
			return nil
		}
	}
	tr := http.DefaultTransport.(*http.Transport).Clone()
	tr.DialContext = dialer.DialContext
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
