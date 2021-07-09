require_relative './ordinal_array/ordinal'
require_relative './ordinal_array/ordinal_constants'

class Array

  include OrdinalArray::Constant
  include OrdinalArray

  def self.respond_to?(method_sym, include_private=false)
    return true if Array.number_in_letter? method_sym
    super
  end

  def method_missing(name, *params)
    if Array.number_in_letter? name
      index = index_by_number_in_letter(name, params)

      self.class.send(:define_method, name) do
        self[index]
      end

      self.send(name)
    else
      super
    end
  end

  private

  def self.number_in_letter?(name)
    ordinal_figure      = false
    possible_followers  = [:hundred, :decade, :ordinal]

    letter_numbers      = name.to_s.split('_').drop_while do |letter_number|
      return false if ordinal_figure

      figure = Numbers_in_letter.element_by_name(letter_number)
      return false unless figure
      return false unless possible_followers.include? figure.to_sym

      possible_followers  = figure.can_be_followed_by
      ordinal_figure      = !figure.kind_of?(ComposedOrdinal)

      true
    end
    letter_numbers.empty? && ordinal_figure
  end

  def index_by_number_in_letter(name, *params)
    partial_sum = 1
    sum = name.to_s.split('_').inject(0) do |sum, letter_number|
      number = Numbers_in_letter.element_by_name(letter_number).number
      if partial_sum < number
        partial_sum = partial_sum * number
      else
        sum = sum + partial_sum
        partial_sum = number
      end
      sum
    end
    sum   = sum + partial_sum
    index = sum - 1
    index > 0 ? index : nil
  end
end
