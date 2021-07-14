require "helper"

describe FilterTable do
  let(:data) do
    [
   { foo: 3, bar: true, baz: "yay", num: nil, snum: "0" },
   { foo: 2, bar: false, baz: "noo", num: 1, snum: nil },
   { foo: 2, bar: false, baz: "whatever", num: 2, snum: "1.00" },
    ]
  end

  let(:resource) do
    Class.new do
      attr_reader :data
      def initialize(data)
        @data = data
      end
    end
  end

  let(:factory) { FilterTable.create }
  let(:instance) { resource.new(data) }

  it "has a create utility which creates a filter factory" do
    _(factory).must_be_kind_of FilterTable::Factory
  end

  it "supports empty arrays" do
    factory.add_accessor(:where).add(:baz).connect(resource, :data)
    _(resource.new([]).where { false }.params).must_equal []
  end

  it "supports nil arrays" do
    factory.add_accessor(:where).add(:baz).connect(resource, :data)
    _(resource.new(nil).where { false }.params).must_equal []
  end

  it "supports range" do
    factory.add_accessor(:where).connect(resource, :data)
    _(instance.where({ foo: (3..5) }).params).must_equal [data[0]]
  end

  it "retrieves the resource from all entries" do
    factory.add_accessor(:where)
      .add(:baz?) { |x| x.resource } # rubocop: disable Style/SymbolProc
      .connect(resource, :data)
    _(instance.baz?).must_equal instance
  end

  describe "when calling add_accessor" do
    it "is chainable" do
      _(factory.add_accessor(:sth)).must_equal factory
    end

    it "wont add nil" do
      _(proc { factory.add_accessor(nil) }).must_throw RuntimeError
    end

    it "can expose the where method" do
      factory.add_accessor(:where).connect(resource, :data)
      _(instance.respond_to?(:where)).must_equal true
      _(instance.where({ baz: "yay" }).params).must_equal [data[0]]
    end

    it "will delegate even non-existing methods" do
      factory.add_accessor(:not_here).connect(resource, :data)
      _(instance.respond_to?(:not_here)).must_equal true
    end
  end

  describe "when calling add" do
    it "is chainable" do
      _(factory.add(:sth)).must_equal factory
    end

    it "wont add nil" do
      _(proc { factory.add(nil) }).must_throw RuntimeError
    end

    it "can expose a data column" do
      factory.add(:baz).connect(resource, :data)
      _(instance.baz(123)).must_be_kind_of(FilterTable::Table)
    end

    it "retrieves all entries" do
      factory.add(:foo).connect(resource, :data)
      _(instance.foo).must_equal([3, 2, 2])
    end

    it "retrieves entries with simple style" do
      factory.add(:foo, style: :simple)
        .add(:num, style: :simple)
        .connect(resource, :data)
      _(instance.foo).must_equal([3, 2])
      _(instance.num).must_equal([1, 2])
    end
  end

  describe "when calling entries" do
    before { factory.add(:baz).connect(resource, :data) }
    let(:entries) { instance.baz(/.*/).entries }
    let(:entry) { instance.baz("yay").entries }

    it "retrieves all entries with this field" do
      _(entries.length).must_equal 3
      _(entry.length).must_equal 1
    end

    it "retrieves all entries with this field" do
      _(entry[0]).must_be_kind_of(Struct)
    end

    it "retrieves all entries with this field" do
      _(entry[0].baz).must_equal "yay"
    end

    it "prints nicely" do
      _(entry[0].to_s).must_match(/ with baz == "yay" one entry/)
    end
  end

  describe "with the number field" do
    before { factory.add(:num).connect(resource, :data) }

    it "filter by nil" do
      _(instance.num(nil).params).must_equal [data[0]]
    end

    it "filter by existing numbers" do
      _(instance.num(1).params).must_equal [data[1]]
    end

    it "filter by missing number" do
      _(instance.num(-1).params).must_equal []
    end
  end

  describe "with the string-number field" do
    before { factory.add(:snum).connect(resource, :data) }

    it "retrieves the number 0" do
      _(instance.snum(0).params).must_equal [data[0]]
    end

    it "retrieves the number 1" do
      _(instance.snum(1).params).must_equal []
    end
  end

  describe "with the string-float field" do
    before { factory.add(:snum).connect(resource, :data) }

    it "retrieves the float 0.0" do
      _(instance.snum(0.0).params).must_equal [data[0]]
    end

    it "retrieves the float 1.0" do
      _(instance.snum(1.0).params).must_equal [data[2]]
    end
  end

  describe "with a regex check" do
    before { factory.add(:baz).connect(resource, :data) }

    it "retrieves the number 0" do
      _(instance.baz(/ever$/).params).must_equal [data[2]]
    end
  end

  describe "with the string field" do
    before { factory.add(:baz).connect(resource, :data) }

    it "filter by existing strings" do
      _(instance.baz("yay").params).must_equal [data[0]]
    end

    it "filter by missing string" do
      _(instance.baz("num").params).must_equal []
    end

    it "filter by existing regex" do
      _(instance.baz(/A/i).params).must_equal [data[0], data[2]]
    end

    it "filter by missing regex" do
      _(instance.baz(/zzz/).params).must_equal []
    end
  end

  describe "with a range filter" do
    before { factory.add(:foo).connect(resource, :data) }

    it "filter and retrieves data with matching range" do
      _(instance.foo((3..5)).params).must_equal [data[0]]
    end

    it "filter and retrieves empty result if no data in matching range" do
      _(instance.foo((4..5)).params).must_equal []
    end
  end
end
