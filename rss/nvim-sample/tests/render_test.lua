-- Run: nvim --headless -u NONE --cmd "set rtp+=rss/nvim-sample" -l rss/nvim-sample/tests/render_test.lua
local strip = require("rss_sample.render").strip
local function eq(got, want)
  assert(vim.deep_equal(got, want), vim.inspect(got) .. " ~= " .. vim.inspect(want))
end
eq(strip("<p>a &amp; b<br>c</p>&#65;"), { "a & b", "c", "", "A" })
eq(strip("<script>x</script>t&unknown;"), { "xt&unknown;" })
print("ok")
