// Package opml reads and writes OPML subscription lists.
package opml

import (
	"encoding/xml"
	"io"
)

// Item is one feed subscription; Category is the nearest enclosing folder.
type Item struct {
	URL      string
	Title    string
	SiteURL  string
	Category string
}

type outline struct {
	Text     string    `xml:"text,attr"`
	Title    string    `xml:"title,attr,omitempty"`
	Type     string    `xml:"type,attr,omitempty"`
	XMLURL   string    `xml:"xmlUrl,attr,omitempty"`
	HTMLURL  string    `xml:"htmlUrl,attr,omitempty"`
	Outlines []outline `xml:"outline"`
}

type document struct {
	XMLName xml.Name  `xml:"opml"`
	Version string    `xml:"version,attr"`
	Title   string    `xml:"head>title"`
	Body    []outline `xml:"body>outline"`
}

func Parse(r io.Reader) ([]Item, error) {
	var doc document
	if err := xml.NewDecoder(r).Decode(&doc); err != nil {
		return nil, err
	}
	var items []Item
	var walk func(os []outline, category string)
	walk = func(os []outline, category string) {
		for _, o := range os {
			if o.XMLURL != "" {
				title := o.Title
				if title == "" {
					title = o.Text
				}
				items = append(items, Item{URL: o.XMLURL, Title: title, SiteURL: o.HTMLURL, Category: category})
				continue
			}
			name := o.Text
			if name == "" {
				name = o.Title
			}
			walk(o.Outlines, name)
		}
	}
	walk(doc.Body, "")
	return items, nil
}

// Write emits items grouped by category, in first-seen category order.
func Write(w io.Writer, title string, items []Item) error {
	doc := document{Version: "2.0", Title: title}
	folders := map[string]int{}
	for _, it := range items {
		o := outline{Text: it.Title, Title: it.Title, Type: "rss", XMLURL: it.URL, HTMLURL: it.SiteURL}
		if it.Category == "" {
			doc.Body = append(doc.Body, o)
			continue
		}
		i, ok := folders[it.Category]
		if !ok {
			i = len(doc.Body)
			folders[it.Category] = i
			doc.Body = append(doc.Body, outline{Text: it.Category, Title: it.Category})
		}
		doc.Body[i].Outlines = append(doc.Body[i].Outlines, o)
	}
	if _, err := io.WriteString(w, xml.Header); err != nil {
		return err
	}
	enc := xml.NewEncoder(w)
	enc.Indent("", "  ")
	return enc.Encode(doc)
}
