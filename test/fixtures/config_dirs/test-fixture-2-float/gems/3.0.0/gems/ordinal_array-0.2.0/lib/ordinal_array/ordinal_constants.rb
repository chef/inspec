require_relative './ordinal'

module OrdinalArray
  module Constant

    First       = Ordinal.new("first", 1)
    One         = ComposedOrdinal.new("one", 1)
    Second      = Ordinal.new("second", 2)
    Two         = ComposedOrdinal.new("two", 2)
    Third       = Ordinal.new("third", 3)
    Three       = ComposedOrdinal.new("three", 3)
    Fourth      = Ordinal.new("fourth", 4)
    Four        = ComposedOrdinal.new("four", 4)
    Fifth       = Ordinal.new("fifth", 5)
    Five        = ComposedOrdinal.new("five", 5)
    Sixth       = Ordinal.new("sixth", 6)
    Six         = ComposedOrdinal.new("six", 6)
    Seventh     = Ordinal.new("seventh", 7)
    Seven       = ComposedOrdinal.new("seven", 7)
    Eighth      = Ordinal.new("eighth", 8)
    Eight       = ComposedOrdinal.new("eight", 8)
    Ninth       = Ordinal.new("ninth", 9)
    Nine        = ComposedOrdinal.new("nine", 9)
    Tenth       = DecadeOrdinal.new("tenth", 10)
    Ten         = ComposedDecadeOrdinal.new("ten", 10)
    Eleventh    = DecadeOrdinal.new("eleventh", 11)
    Eleven      = ComposedDecadeOrdinal.new("eleven", 11)
    Twelfth     = DecadeOrdinal.new("twelfth", 12)
    Twelve      = ComposedDecadeOrdinal.new("twelve", 12)
    Thirteenth  = DecadeOrdinal.new("thirteenth", 13)
    Thirteen    = ComposedDecadeOrdinal.new("thirteen", 13)
    Fourteenth  = DecadeOrdinal.new("fourteenth", 14)
    Fourteen    = ComposedDecadeOrdinal.new("fourteen", 14)
    Fifteenth   = DecadeOrdinal.new("fifteenth", 15)
    Fifteen     = ComposedDecadeOrdinal.new("fifteen", 15)
    Sixteenth   = DecadeOrdinal.new("sixteenth", 16)
    Sixteen     = ComposedDecadeOrdinal.new("sixteen", 16)
    Seventeenth = DecadeOrdinal.new("seventeenth", 17)
    Seventeen   = ComposedDecadeOrdinal.new("seventeen", 17)
    Eighteenth  = DecadeOrdinal.new("eighteenth", 18)
    Eighteen    = ComposedDecadeOrdinal.new("eighteen", 18)
    Nineteenth  = DecadeOrdinal.new("nineteenth", 19)
    Nineteen    = ComposedDecadeOrdinal.new("nineteen", 19)
    Twentieth   = DecadeOrdinal.new("twentieth", 20)
    Twenty      = ComposedDecadeOrdinal.new("twenty", 20)
    Thirtieth   = DecadeOrdinal.new("thirtieth", 30)
    Thirty      = ComposedDecadeOrdinal.new("thirty", 30)
    Fortieth    = DecadeOrdinal.new("fortieth", 40)
    Fourty      = ComposedDecadeOrdinal.new("fourty", 40)
    Fiftieth    = DecadeOrdinal.new("fiftieth", 50)
    Fifty       = ComposedDecadeOrdinal.new("fifty", 50)
    Sixtieth    = DecadeOrdinal.new("sixtieth", 60)
    Sixty       = ComposedDecadeOrdinal.new("sixty", 60)
    Seventieth  = DecadeOrdinal.new("seventieth", 70)
    Seventy     = ComposedDecadeOrdinal.new("seventy", 70)
    Eightieth   = DecadeOrdinal.new("eightieth", 80)
    Eighty      = ComposedDecadeOrdinal.new("eighty", 80)
    Ninetieth   = DecadeOrdinal.new("ninetieth", 90)
    Ninety      = ComposedDecadeOrdinal.new("ninety", 90)
    Hundredth   = HundredOrdinal.new("hundredth", 100)
    Hundred     = ComposedHundredOrdinal.new("hundred", 100)

    Numbers_in_letter = [
      One, Two, Three, Four, Five, Six, Seven, Eight, Nine,
      Ten, Eleven, Twelve, Thirteen, Fourteen, Fifteen, Sixteen, Seventeen, Eighteen, Nineteen,
      Twenty, Thirty, Fourty, Fifty, Sixty, Seventy, Eighty, Ninety,
      Hundred,

      First, Second, Third, Fourth, Fifth, Sixth, Seventh, Eighth, Ninth,
      Tenth, Eleventh, Twelfth, Thirteenth, Fourteenth, Fifteenth, Sixteenth, Seventeenth, Eighteenth, Nineteenth,
      Twentieth, Thirtieth, Fortieth, Fiftieth, Sixtieth, Seventieth, Eightieth, Ninetieth,
      Hundredth
    ]

    class << Numbers_in_letter
      def element_by_name(name)
        index = self.index {|n| n.number_in_letter == name }
        return nil unless index
        self.[](index)
      end
    end

  end
end
