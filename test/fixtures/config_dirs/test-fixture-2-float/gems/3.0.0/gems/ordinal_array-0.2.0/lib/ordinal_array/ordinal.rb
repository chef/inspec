module OrdinalArray

  class Ordinal
    attr_accessor :number_in_letter, :number, :can_be_followed_by

    def initialize(number_in_letter, number)
      @number_in_letter   = number_in_letter
      @can_be_followed_by = nil
      @number = number
    end

    def to_sym
      :ordinal
    end
  end

  class ComposedOrdinal < Ordinal
    def initialize(number_in_letter, number)
      super(number_in_letter, number)
      @can_be_followed_by = [:hundred]
    end

    def to_sym
      :ordinal
    end
  end

  class DecadeOrdinal < Ordinal
    def initialize(number_in_letter, number)
      super(number_in_letter, number)
      @can_be_followed_by = nil
    end

    def to_sym
      :decade
    end
  end

  class ComposedDecadeOrdinal < ComposedOrdinal
    def initialize(number_in_letter, number)
      super(number_in_letter, number)
      @can_be_followed_by = [:ordinal]
    end

    def to_sym
      :decade
    end
  end

  class HundredOrdinal < Ordinal
    def initialize(number_in_letter, number)
      super(number_in_letter, number)
      @can_be_followed_by = nil
    end

    def to_sym
      :hundred
    end
  end

  class ComposedHundredOrdinal < ComposedDecadeOrdinal
    def initialize(number_in_letter, number)
      super(number_in_letter, number)
      @can_be_followed_by = [:decade, :ordinal]
    end

    def to_sym
      :hundred
    end
  end
end
