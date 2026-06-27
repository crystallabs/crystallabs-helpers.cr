require "./spec_helper"

# A flags enum used to exercise the Enums helpers.
@[Flags]
enum SpecColor
  Red
  Green
  Blue
end

private class BooleanHolder
  include Crystallabs::Helpers::Boolean
end

private class WidgetWithEnum
  # ameba:disable Lint/UselessAssign -- macro arg `name : Enum = Default` mis-read as a useless local assignment
  Crystallabs::Helpers::Enums.enum_property color : SpecColor = SpecColor::Red

  def initialize(color : SpecColor | Crystallabs::Helpers::Enums::Shorthands = @color)
    self.color = color
  end
end

private class Loggy
  include Crystallabs::Helpers::Logging

  def describe_it(a, b)
    my a, b
  end
end

private class Person
  include Crystallabs::Helpers::Alias_Methods

  getter name : String

  def initialize(@name : String)
  end

  alias_method full_name, name

  def greeting
    "hi #{name}"
  end

  alias_previous hello
end

describe Crystallabs::Helpers do
  describe Crystallabs::Helpers::Logging do
    it "renders the method name and inspected arguments" do
      Loggy.new.describe_it(1, "x").should eq %(describe_it: a=1 b="x")
    end
  end

  describe Crystallabs::Helpers::Boolean do
    b = BooleanHolder.new

    it "converts strings" do
      b.to_b("1").should be_true
      b.to_b("true").should be_true
      b.to_b("yes").should be_true
      b.to_b("0").should be_false
      b.to_b("-0").should be_false
      b.to_b("0n").should be_false
      b.to_b("false").should be_false
      b.to_b(" ").should be_false
      b.to_b("").should be_false
    end

    it "honors the empty fallback for blank strings" do
      b.to_b("", empty: true).should be_true
      b.to_b("", empty: false).should be_false
    end

    it "treats whitespace-only strings as blank, honoring the empty fallback" do
      b.to_b("   ").should be_false
      b.to_b("\t").should be_false
      b.to_b(" ", empty: true).should be_true
    end

    it "converts integers" do
      b.to_b(0).should be_false
      b.to_b(1).should be_true
      b.to_b(-5).should be_true
    end

    it "converts chars" do
      b.to_b('0').should be_false
      b.to_b('1').should be_true
    end

    it "forwards the empty fallback for blank (whitespace) chars" do
      b.to_b(' ', empty: true).should be_true
      b.to_b(' ', empty: false).should be_false
    end

    it "converts nil and bools" do
      b.to_b(nil).should be_false
      b.to_b(true).should be_true
      b.to_b(false).should be_false
    end

    it "accepts the empty keyword uniformly across overloads (incl. Bool)" do
      b.to_b(true, empty: true).should be_true
      b.to_b(false, empty: true).should be_false
    end

    it "honors the empty fallback for nil (the canonical blank value)" do
      b.to_b(nil, empty: true).should be_true
      b.to_b(nil, empty: false).should be_false
    end

    it "converts bools to ints" do
      b.to_i(true).should eq 1
      b.to_i(false).should eq 0
    end
  end

  describe Crystallabs::Helpers::Enums do
    it "passes through a value already of the enum type" do
      Crystallabs::Helpers::Enums.from(SpecColor, SpecColor::Green).should eq SpecColor::Green
    end

    it "converts a symbol shorthand" do
      Crystallabs::Helpers::Enums.from(SpecColor, :red).should eq SpecColor::Red
    end

    it "converts a string shorthand case-insensitively" do
      Crystallabs::Helpers::Enums.from(SpecColor, "GREEN").should eq SpecColor::Green
    end

    it "ORs a collection of shorthands" do
      Crystallabs::Helpers::Enums.from(SpecColor, {:red, :blue}).should eq(SpecColor::Red | SpecColor::Blue)
    end

    it "mixes symbols and strings in a collection" do
      Crystallabs::Helpers::Enums.from(SpecColor, [:red, "blue"]).should eq(SpecColor::Red | SpecColor::Blue)
    end

    it "yields the zero value for an empty collection" do
      Crystallabs::Helpers::Enums.from(SpecColor, [] of Crystallabs::Helpers::Enums::Shorthand).should eq SpecColor::None
    end

    describe "enum_property" do
      it "defaults to the declared value" do
        WidgetWithEnum.new.color.should eq SpecColor::Red
      end

      it "accepts a shorthand via the setter" do
        w = WidgetWithEnum.new
        w.color = :green
        w.color.should eq SpecColor::Green
      end

      it "accepts a collection of shorthands" do
        w = WidgetWithEnum.new
        w.color = {:red, :blue}
        w.color.should eq(SpecColor::Red | SpecColor::Blue)
      end

      it "accepts a shorthand via the initializer" do
        WidgetWithEnum.new("blue").color.should eq SpecColor::Blue
      end

      it "still accepts a real enum value" do
        w = WidgetWithEnum.new
        w.color = SpecColor::Blue
        w.color.should eq SpecColor::Blue
      end
    end
  end

  describe Crystallabs::Helpers::Alias_Methods do
    it "aliases a method" do
      p = Person.new("John")
      p.name.should eq "John"
      p.full_name.should eq "John"
    end

    it "aliases the previously defined method" do
      Person.new("John").hello.should eq "hi John"
    end
  end
end
