local view = require("sidebar-nvim.view")
local config = require("sidebar-nvim.config")
local utils = require("sidebar-nvim.utils")
local profile = require("sidebar-nvim.profile")

local api = vim.api

local namespace_id = api.nvim_create_namespace("SidebarNvimHighlights")

local M = {}

-- extracted from this PR: https://github.com/sidebar-nvim/sidebar.nvim/pull/41
-- thanks @lambdahands
local function sanitize_lines(lines)
    local lines_ = {}
    for _, line_ in ipairs(lines) do
        local line = string.gsub(line_, "[\n\r]", " ")
        table.insert(lines_, line)
    end
    return lines_
end

local function expand_section_lines(section_lines, lines_offset)
    if type(section_lines) == "string" then
        return vim.split(section_lines, "\n"), nil
    elseif type(section_lines) == "table" and section_lines.lines == nil then
        return sanitize_lines(section_lines), nil
    end

    -- we have here section_lines = { lines = string|table of strings, hl = table }

    local section_hl = section_lines.hl or {}
    section_lines = section_lines.lines

    if type(section_lines) == "string" then
        section_lines = vim.split(section_lines, "\n")
    else
        section_lines = sanitize_lines(section_lines)
    end

    -- we must offset the hl lines so it matches the current section position
    for _, hl_entry in ipairs(section_hl) do
        hl_entry[2] = hl_entry[2] + lines_offset
    end

    return section_lines, section_hl
end

local function build_section_title(section)
    local icon = "#"
    if section.icon ~= nil then
        icon = section.icon
    end

    if type(icon) == "function" then
        icon = icon()
    end

    return icon .. " " .. section.title
end

-- luacheck: push ignore section
local function build_section_separator(section)
    if type(config.section_separator) == "string" then
        return config.section_separator
    end

    if type(config.section_separator) == "table" then
        return config.section_separator
    end

    if type(config.section_separator) ~= "function" then
        utils.echo_warning("'section_separator' must be string, table or function")
        return
    end

    return config.section_separator(section)
end
-- luacheck: pop

local function get_lines_and_hl(sections_data)
    local lines = {}
    local hl = {}
    local section_line_indexes = {}

    for index, data in ipairs(sections_data) do
        local section_title = build_section_title(data.section)

        table.insert(hl, { "SidebarNvimSectionTitle", #lines, 0, #section_title })

        local section_content_start = #lines + 3 -- +3 white spaces
        local section_title_start = #lines + 1
        table.insert(lines, section_title)
        table.insert(lines, "")

        local section_lines, section_hl = expand_section_lines(data.lines, #lines)

        table.insert(section_line_indexes, {
            content_start = section_content_start,
            content_length = #section_lines,
            section_start = section_title_start,
            section_length = #section_lines + 4, -- +4 whitespaces
        })

        for _, line in ipairs(section_lines) do
            table.insert(lines, line)
        end

        for _, hl_entry in ipairs(section_hl or {}) do
            table.insert(hl, hl_entry)
        end

        if index ~= #sections_data then
            local separator = build_section_separator(data.section)

            if type(separator) == "table" then
                for _, line in ipairs(separator) do
                    table.insert(hl, { "SidebarNvimSectionSeperator", #lines, 0, #line })
                    table.insert(lines, line)
                end
            else
                table.insert(hl, { "SidebarNvimSectionSeperator", #lines + 1, 0, #separator })
                table.insert(lines, separator)
            end
        end
    end

    return lines, hl, section_line_indexes
end

function M.draw(sections_data)
    return profile.run("view.render", function()
        if not api.nvim_buf_is_loaded(view.View.bufnr) then
            return
        end

        local cursor
        if view.is_win_open() then
            cursor = api.nvim_win_get_cursor(view.get_winnr())
        end

        local lines, hl, section_line_indexes = get_lines_and_hl(sections_data)

        api.nvim_buf_set_option(view.View.bufnr, "modifiable", true)
        api.nvim_buf_set_lines(view.View.bufnr, 0, -1, false, lines)
        M.render_hl(view.View.bufnr, hl)
        api.nvim_buf_set_option(view.View.bufnr, "modifiable", false)

        if view.is_win_open() then
            if cursor and #lines >= cursor[1] then
                api.nvim_win_set_cursor(view.get_winnr(), cursor)
            end
            if cursor then
                api.nvim_win_set_option(view.get_winnr(), "wrap", false)
            end

            if config.hide_statusline then
                api.nvim_win_set_option(view.get_winnr(), "statusline", "%#NonText#")
            end
        end

        return section_line_indexes
    end)
end

function M.render_hl(bufnr, hl)
    bufnr = bufnr or 0
    if not api.nvim_buf_is_loaded(bufnr) then
        return
    end
    api.nvim_buf_clear_namespace(bufnr, namespace_id, 0, -1)
    for _, data in ipairs(hl) do
        api.nvim_buf_add_highlight(bufnr, namespace_id, data[1], data[2], data[3], data[4])
    end
end

return M
