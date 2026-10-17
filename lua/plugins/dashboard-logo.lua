-- Custom portrait header. Keep AstroNvim's dashboard actions and development setup.
local header_lines = {
  "         ⣠⠴⠒⣢⠤⠒⠒⠢⣄⠢⡀",
  "       ⢠⠞⠁⣠⠏⠁    ⠈⠃⠃",
  "       ⠸  ⣣⠔⠒⠒⠒⢤⣠⠤⠒⠤⠤⣀⡀",
  "   ⣠⠖⠊⠉⠉⠳⠄⢣⣀⣀⣀⣀⣂⣐     ⠹⠤⠤⠤⣄⡀",
  "⢠⠖⢒⠃⠄⣀⠤⠔⠒⠉       ⠉⠉⠒⠦⢌⣁⡘   ⠙⢦",
  "⠈⢀⡬⠓⠋                  ⠉⠓⠦⣄⠠⠌⠓⠒⢦⡀",
  "⠐⠉                        ⠈⠙⢦⡁  ⠙⣆",
  "                             ⠙⢦⡀⡀⢸⡀",
  "       ⡠⢠⠂  ⡀                  ⠳⡄⠆⠉⢧⡀",
  "     ⢠⠎⡴⠃ ⣠⠞⡸              ⢀    ⠹⡄  ⢣",
  "    ⡰⢃⠞ ⣠⠞⠁ ⡇              ⠘⡄    ⠙⡄⠄⢼  ⡀",
  "   ⠰⢁⣀⡴⠚⠁   ⡇ ⡇         ⢠⢤⠃ ⢱  ⢀⣀ ⢹⠢⠨⠏⠉⢹",
  "  ⢰⠒⠉  ⣠⣤⣤⡀ ⢱⡀⡁⡠        ⡸⠘⡄ ⠈⣶⢻⣮⠙ ⠈⡆   ⢸",
  "  ⡇   ⣾⣿⣿⣿⡇  ⢳⢡⢳⡀   ⡇  ⡴⠃ ⢱ ⠐⡎⠉⠁⢠ ⡄⢣⠰⡐⢄⣸",
  "⠠ ⡇  ⢸⣿⣿⣿⣿⠇     ⠹⣄  ⠃⣠⠞⠁   ⢣ ⡇  ⢸ ⡇⢸ ⡇  ⠙⠦⣄",
  "⠸⠑⠃⡀ ⢸⣿⣿⣿⡟       ⠈⠓⠦⠼ ⢠⣶⣶⣶⡄⠈⢧   ⢸⢸⠁⠈⡆⡇⠴⡄  ⠈⠳⣄",
  " ⡂⠅⡂⠅⡀⠉⠛⠉            ⢀⣿⣿⣿⣿⡇ ⠈⢧  ⡎⡸  ⣏⢍ ⠈⠒⠦⣀ ⠘⠦⡄",
  " ⠂⠅⠂⠅⠂               ⢸⣿⣿⣿⣿⠃  ⢸ ⡼⢡⠃  ⡜⠲⠬⣉⡑⠂⢀⣉⣒⣨⠽",
  "⠸⡄                   ⠘⢿⣿⡿⠋   ⠧⡼⢰⠃   ⡇ ⢇ ⠈⢉⣡⡀",
  " ⠙⢦⡀                    ⠄⡂⠄⡂ ⢠⠃     ⡇⡀⠘⡄⢀⠏ ⠳⡄",
  " ⡰⠒⢬⡗⢠                  ⠁⠂⠅⡂⣡⠏  ⣀⠜⡜⡸ ⢳⡀⢱⠸⡀ ⢀⠙⢦",
  "⠠⠇  ⠘⡰⠚⠙⣆ ⢀               ⢀⣨⠥⠤⠒⠚⢉⡜⡰⢣⠆ ⠹⡄⢧⠳⡀⠣⠥⠘⠈⠁",
  "    ⢠⠃  ⠈⡳⣠⢲⣀⣀⣀⡤⠤⢤⠠⠤⢤⠤⠤⠤⠔⠊⠉⢀⡔  ⠐⢪ ⢱⢸   ⠙⠌⢧⠙⡄ ⠸⠉⠁",
  "⠰  ⠠⠏⠤⠤⠂⠤⠒⠓⠬⠎  ⠈⠁⠇⠤⠤⠘⠢⠤    ⠞⠄   ⠼ ⠈⠆⠇  ⠴⠢⠈⠳⠄ ⠤⠒⠂",
}

-- Snacks centers each header row separately. Keep the entire image rectangular
-- so each row receives exactly the same horizontal offset. Use display cells,
-- never UTF-8 byte lengths, and generate padding at runtime (editors may trim it).
local width = 0
for _, line in ipairs(header_lines) do
  width = math.max(width, vim.fn.strdisplaywidth(line))
end
for index, line in ipairs(header_lines) do
  header_lines[index] = line .. string.rep(" ", width - vim.fn.strdisplaywidth(line))
end
local header = table.concat(header_lines, "\n")

return {
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      opts.dashboard = opts.dashboard or {}
      opts.dashboard.preset = opts.dashboard.preset or {}
      opts.dashboard.preset.header = header
      -- Keep a 24-line portrait and all six menu items usable on a laptop.
      for _, section in ipairs(opts.dashboard.sections or {}) do
        if section.section == "header" then
          section.padding = 1
        elseif section.section == "keys" then
          section.gap = 0
          section.padding = 1
        end
      end
    end,
  },
}
