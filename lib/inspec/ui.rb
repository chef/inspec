module Inspec
  # Provides simple terminal UI interaction primitives for CLI commands and plugins.
  class UI
    ANSI_CODES = {
      reset: "\e[0m",
      bold: "\e[1m",
      color: {
        red: "\e[38;5;9m", # 256-color light red
        green: "\e[38;5;41m",  # 256-color light green
        yellow: "\e[33m",
        cyan: "\e[36m",
        white: "\e[37m",
        grey: "\e[38;5;247m",  # 256-color medium grey
      },
    }.freeze

    GLYPHS = {
      bullet: "•", # BULLET, Unicode: U+2022, UTF-8: E2 80 A2
      check: "✔", #  HEAVY CHECK MARK, Unicode: U+2714, UTF-8: E2 9C 94
      swirl: "↺", # ANTICLOCKWISE OPEN CIRCLE ARROW, Unicode U+21BA, UTF-8: E2 86 BA
      script_x: "×", # MULTIPLICATION SIGN, Unicode: U+00D7, UTF-8: C3 97
      question: "?", # normal ASCII question mark
      em_dash: "─", # BOX DRAWINGS LIGHT HORIZONTAL Unicode: U+2500, UTF-8: E2 94 80
      heavy_dash: "≖", # RING IN EQUAL TO, Unicode: U+2256, UTF-8: E2 89 96
      vertical_dash: "│", # BOX DRAWINGS LIGHT VERTICAL, Unicode: U+2502, UTF-8: E2 94 82
      table_corner: "⨀", # N-ARY CIRCLED DOT OPERATOR, Unicode: U+2A00, UTF-8: E2 A8 80
    }.freeze

    EXIT_NORMAL = 0
    EXIT_USAGE_ERROR = 1
    EXIT_PLUGIN_ERROR = 2
    EXIT_FATAL_DEPRECATION = 3
    EXIT_LICENSE_NOT_ACCEPTED = 172
    EXIT_FAILED_TESTS = 100
    EXIT_SKIPPED_TESTS = 101

    attr_reader :io

    def initialize(opts = {})
      @color = opts[:color].nil? ? true : opts[:color]
      @interactive = opts[:interactive].nil? ? $stdout.isatty : opts[:interactive]
      @io = opts[:io] || $stdout
    end

    def color?
      @color
    end

    def print_or_return(str, print_flag)
      io.print(str) if print_flag
      str
    end

    #=========================================================================#
    #                   Low-level formatting methods
    #=========================================================================#

    def plain(str, opts = { print: true })
      print_or_return(str.to_s, opts[:print])
    end

    def plain_line(str = "", opts = { print: true })
      print_or_return(str.to_s + "\n", opts[:print])
    end

    def bold(str, opts = { print: true })
      result = color? ? io.print(ANSI_CODES[:bold] + str.to_s + ANSI_CODES[:reset]) : str.to_s
      print_or_return(result, opts[:print])
    end

    ANSI_CODES[:color].keys.each do |color|
      define_method(color) do |str, opts = { print: true }|
        result = color? ? (ANSI_CODES[:color][color] + str.to_s + ANSI_CODES[:reset]) : str.to_s
        print_or_return(result, opts[:print])
      end
    end

    # Allows bold and color
    ANSI_CODES[:color].keys.each do |color|
      define_method("bold_#{color}") do |str, opts = { print: true }|
        result = color? ? (ANSI_CODES[:bold] + ANSI_CODES[:color][color] + str.to_s + ANSI_CODES[:reset]) : str.to_s
        print_or_return(result, opts[:print])
      end
    end

    #=========================================================================#
    #                   High-Level formatting methods
    #=========================================================================#

    def emphasis(str, opts = { print: false })
      cyan(str, opts)
    end

    def headline(str, opts = { print: true })
      str = str.dup.to_s
      if str.length < 76
        dash_length = 80 - str.length - 4 # 4 spaces
        dash_length /= 2
      else
        dash_length = 0
      end

      result = "\n"
      result += " " + (color? ? GLYPHS[:em_dash] : "-") * dash_length + " "
      result += color? ? ANSI_CODES[:bold] + ANSI_CODES[:color][:white] : ""
      result += str
      result += color? ? ANSI_CODES[:reset] : ""
      result += " " + (color? ? GLYPHS[:em_dash] : "-") * dash_length + " "
      result += "\n\n"

      print_or_return(result, opts[:print])
    end

    # Issues a one-line message, with 'ERROR: ' prepended in bold red.
    def error(str, opts = { print: true })
      str = str.dup.to_s
      result = ""
      result += color? ? ANSI_CODES[:bold] + ANSI_CODES[:color][:red] : ""
      result += "ERROR:"
      result += color? ? ANSI_CODES[:reset] : ""
      result += " "
      result += str
      result += "\n"
      print_or_return(result, opts[:print])
    end

    # Issues a one-line message, with 'WARNING: ' prepended in bold yellow.
    def warning(str, opts = { print: true })
      str = str.dup.to_s
      result = ""
      result += color? ? ANSI_CODES[:bold] + ANSI_CODES[:color][:yellow] : ""
      result += "WARNING:"
      result += color? ? ANSI_CODES[:reset] : ""
      result += " "
      result += str
      result += "\n"
      print_or_return(result, opts[:print])
    end

    # Draws a horizontal line.
    def line(opts = { print: true })
      if color?
        result = ANSI_CODES[:bold] + GLYPHS[:heavy_dash] * 80 + ANSI_CODES[:reset] + "\n"
      else
        result = "-" * 80 + "\n"
      end
      print_or_return(result, opts[:print])
    end

    # Makes a bullet point.
    def list_item(str, opts = { print: true })
      bullet = color? ? ANSI_CODES[:bold] + ANSI_CODES[:color][:white] + GLYPHS[:bullet] + ANSI_CODES[:reset] : "*"
      result = " " + bullet + " " + str.to_s + "\n"
      print_or_return(result, opts[:print])
    end

    # Makes a table.  Call with a block; block arg will be a TTY::Table object,
    # with an extension for setting the header.
    # Typical use:
    # ui.table do |t|
    #   t.header = ['Name', 'Rank', 'Cereal Number']
    #   t << ['Crunch', 'Captain', 1]
    #   t << ['', '', 1]
    #  end
    def table(opts = { print: true })
      require "inspec/ui_table_helper"

      the_table = TableHelper.new
      yield(the_table)

      colorizer = proc do |data, row, _col|
        if color? && row == 0
          ANSI_CODES[:bold] + ANSI_CODES[:color][:white] + data.to_s + ANSI_CODES[:reset]
        else
          data
        end
      end
      render_mode = color? ? :unicode : :ascii
      padding = [0, 1, 0, 1] # T R B L
      result = the_table.render(render_mode, filter: colorizer, padding: padding) + "\n"
      print_or_return(result, opts[:print])
    end

    #=========================================================================#
    #                        Exit Codes
    #=========================================================================#

    def exit(code_sym = :normal)
      # If it's a number, give them a pass for now.
      if code_sym.is_a? Numeric
        code_int = code_sym
      else
        code_const = ("EXIT_" + code_sym.to_s.upcase).to_sym
        unless self.class.const_defined?(code_const)
          warning("Unrecognized exit constant #{code_const} - exit with code 1")
          exit(:usage_error)
        end
        code_int = self.class.const_get(code_const)
      end
      Kernel.exit(code_int)
    end

    #=========================================================================#
    #                        Interactivity
    #=========================================================================#
    def interactive?
      @interactive
    end

    # This simply returns a TTY::Prompt object, gated on interactivity being enabled.
    def prompt
      unless interactive?
        raise Inspec::UserInteractionRequired, "Somthing is trying to ask the user a question, but interactivity is disabled."
      end

      require "tty-prompt"

      @prompt ||= TTY::Prompt.new
    end
  end
end
