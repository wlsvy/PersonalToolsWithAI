package api

import (
	"io/fs"
	"mime"
	"net/http"
	"os"
	"path"
	"strings"
)

func init() {
	// Go's mime table lacks it; browsers expect this type for the PWA manifest.
	mime.AddExtensionType(".webmanifest", "application/manifest+json")
}

// spa serves files from dir and falls back to index.html for unknown paths,
// so client-side (history mode) routes survive a reload.
func spa(dir string) http.Handler {
	fsys := os.DirFS(dir)
	files := http.FileServerFS(fsys)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		name := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
		if name != "" && fs.ValidPath(name) {
			if st, err := fs.Stat(fsys, name); err == nil && !st.IsDir() {
				files.ServeHTTP(w, r)
				return
			}
		}
		http.ServeFileFS(w, r, fsys, "index.html")
	})
}
