# frozen_string_literal: true

RSpec.describe RuboCop::Cop::Style::WordArray, :config do
  subject(:cop) { described_class.new(config) }

  before do
    # Reset data which is shared by all instances of WordArray
    described_class.largest_brackets = -Float::INFINITY
  end

  let(:other_cops) do
    {
      'Style/PercentLiteralDelimiters' => {
        'PreferredDelimiters' => {
          'default' => '()'
        }
      }
    }
  end

  context 'when EnforcedStyle is percent' do
    let(:cop_config) do
      { 'MinSize' => 0,
        'WordRegex' => /\A[\p{Word}\n\t]+\z/,
        'EnforcedStyle' => 'percent' }
    end

    it 'registers an offense for arrays of single quoted strings' do
      inspect_source("['one', 'two', 'three']")
      expect(cop.offenses.size).to eq(1)
      expect(cop.messages).to eq(['Use `%w` or `%W` for an array of words.'])
      expect(cop.config_to_allow_offenses).to eq('EnforcedStyle' => 'brackets')
    end

    it 'registers an offense for arrays of double quoted strings' do
      expect_offense(<<-RUBY.strip_indent)
        ["one", "two", "three"]
        ^^^^^^^^^^^^^^^^^^^^^^^ Use `%w` or `%W` for an array of words.
      RUBY
    end

    it 'registers an offense for arrays of unicode word characters' do
      expect_offense(<<-RUBY.strip_indent)
        ["ВУЗ", "вуз", "中文网"]
        ^^^^^^^^^^^^^^^^^^^^^ Use `%w` or `%W` for an array of words.
      RUBY
    end

    it 'registers an offense for arrays with character constants' do
      expect_offense(<<-'RUBY'.strip_indent)
        ["one", ?\n]
        ^^^^^^^^^^^^ Use `%w` or `%W` for an array of words.
      RUBY
    end

    it 'registers an offense for strings with embedded newlines and tabs' do
      inspect_source(%(["one\n", "hi\tthere"]))
      expect(cop.offenses.size).to eq(1)
    end

    it 'registers an offense for strings with newline and tab escapes' do
      expect_offense(<<-'RUBY'.strip_indent)
        ["one\n", "hi\tthere"]
        ^^^^^^^^^^^^^^^^^^^^^^ Use `%w` or `%W` for an array of words.
      RUBY
    end

    it 'uses %W when autocorrecting strings with newlines and tabs' do
      new_source = autocorrect_source(%(["one\\n", "hi\\tthere"]))
      expect(new_source).to eq('%W(one\\n hi\\tthere)')
    end

    it 'does not register an offense for array of non-words' do
      expect_no_offenses('["one space", "two", "three"]')
    end

    it 'does not register an offense for array containing non-string' do
      expect_no_offenses('["one", "two", 3]')
    end

    it 'does not register an offense for array starting with %w' do
      expect_no_offenses('%w(one two three)')
    end

    it 'does not register an offense for array with one element' do
      expect_no_offenses('["three"]')
    end

    it 'does not register an offense for array with empty strings' do
      expect_no_offenses('["", "two", "three"]')
    end

    # Bug: https://github.com/bbatsov/rubocop/issues/4481
    it 'does not register an offense in an ambiguous block context' do
      expect_no_offenses('foo ["bar", "baz"] { qux }')
    end

    it 'registers an offense in a non-ambiguous block context' do
      expect_offense(<<-RUBY.strip_indent)
        foo(['bar', 'baz']) { qux }
            ^^^^^^^^^^^^^^ Use `%w` or `%W` for an array of words.
      RUBY
    end

    it 'does not register offense for array with allowed number of strings' do
      cop_config['MinSize'] = 4
      expect_no_offenses('["one", "two", "three"]')
    end

    it 'does not register an offense for an array with comments in it' do
      expect_no_offenses(<<-RUBY.strip_indent)
        [
        "foo", # comment here
        "bar", # this thing was done because of a bug
        "baz" # do not delete this line
        ]
      RUBY
    end

    it 'registers an offense for an array with comments outside of it' do
      inspect_source(<<-RUBY.strip_indent)
        [
        "foo",
        "bar",
        "baz"
        ] # test
      RUBY

      expect(cop.offenses.size).to eq(1)
    end

    it 'auto-corrects an array of words' do
      new_source = autocorrect_source("['one', %q(two), 'three']")
      expect(new_source).to eq('%w(one two three)')
    end

    it 'auto-corrects an array of words and character constants' do
      new_source = autocorrect_source('[%|one|, %Q(two), ?\n, ?\t]')
      expect(new_source).to eq('%W(one two \n \t)')
    end

    it 'keeps the line breaks in place after auto-correct' do
      new_source = autocorrect_source(["['one',",
                                       "'two', 'three']"])
      expect(new_source).to eq(['%w(one',
                                'two three)'].join("\n"))
    end

    it 'auto-corrects an array of words in multiple lines' do
      new_source = autocorrect_source(<<-RUBY)
        [
        "foo",
        "bar",
        "baz"
        ]
      RUBY
      expect(new_source).to eq(<<-RUBY)
        %w(
        foo
        bar
        baz
        )
      RUBY
    end

    it 'detects right value of MinSize to use for --auto-gen-config' do
      inspect_source(<<-RUBY.strip_indent)
        ['one', 'two', 'three']
        %w(a b c d)
      RUBY
      expect(cop.offenses.size).to eq(1)
      expect(cop.messages).to eq(['Use `%w` or `%W` for an array of words.'])
      expect(cop.config_to_allow_offenses).to eq('EnforcedStyle' => 'percent',
                                                 'MinSize' => 4)
    end

    it 'detects when the cop must be disabled to avoid offenses' do
      inspect_source(<<-RUBY.strip_indent)
        ['one', 'two', 'three']
        %w(a b)
      RUBY
      expect(cop.offenses.size).to eq(1)
      expect(cop.messages).to eq(['Use `%w` or `%W` for an array of words.'])
      expect(cop.config_to_allow_offenses).to eq('Enabled' => false)
    end

    it "doesn't fail in wacky ways when multiple cop instances are used" do
      # Regression test for GH issue #2740
      cop1 = described_class.new(config)
      cop2 = described_class.new(config)
      RuboCop::Formatter::DisabledConfigFormatter.config_to_allow_offenses = {}
      RuboCop::Formatter::DisabledConfigFormatter.detected_styles = {}
      # Don't use `inspect_source`; it resets `config_to_allow_offenses` each
      #   time, which suppresses the bug we are checking for
      _investigate(cop1, parse_source("['g', 'h']"))
      _investigate(cop2, parse_source('%w(a b c)'))
      expect(cop2.config_to_allow_offenses).to eq('EnforcedStyle' => 'percent',
                                                  'MinSize' => 3)
    end
  end

  context 'when EnforcedStyle is array' do
    let(:cop_config) do
      { 'MinSize' => 0,
        'WordRegex' => /\A[\p{Word}]+\z/,
        'EnforcedStyle' => 'brackets' }
    end

    it 'does not register an offense for arrays of single quoted strings' do
      expect_no_offenses("['one', 'two', 'three']")
    end

    it 'does not register an offense for arrays of double quoted strings' do
      expect_no_offenses('["one", "two", "three"]')
    end

    it 'registers an offense for a %w() array' do
      expect_offense(<<-RUBY.strip_indent)
        %w(one two three)
        ^^^^^^^^^^^^^^^^^ Use `[]` for an array of words.
      RUBY
    end

    it 'auto-corrects a %w() array' do
      new_source = autocorrect_source('%w(one two three)')
      expect(new_source).to eq("['one', 'two', 'three']")
    end

    it 'autocorrects a %w() array which uses single quotes' do
      new_source = autocorrect_source("%w(one's two's three's)")
      expect(new_source).to eq('["one\'s", "two\'s", "three\'s"]')
    end

    it 'autocorrects a %W() array which uses escapes' do
      new_source = autocorrect_source('%W(\\n \\t \\b \\v \\f)')
      expect(new_source).to eq('["\n", "\t", "\b", "\v", "\f"]')
    end

    it "doesn't fail on strings which are not valid UTF-8" do
      # Regression test, see GH issue 2671
      expect_no_offenses(<<-'RUBY'.strip_indent)
        ["\xC0",
         "\xC2\x4a",
         "\xC2\xC2",
         "\x4a\x82",
         "\x82\x82",
         "\xe1\x82\x4a",
        ]
      RUBY
    end

    it "doesn't fail on strings which are not valid UTF-8" \
       'and encoding: binary is specified' do
      expect_no_offenses(<<-'RUBY'.strip_indent)
        # -*- encoding: binary -*-
        ["\xC0",
         "\xC2\x4a",
         "\xC2\xC2",
         "\x4a\x82",
         "\x82\x82",
         "\xe1\x82\x4a",
        ]
      RUBY
    end
  end

  context 'with a custom WordRegex configuration' do
    let(:cop_config) { { 'MinSize' => 0, 'WordRegex' => /\A[\w@.]+\z/ } }

    it 'registers an offense for arrays of email addresses' do
      expect_offense(<<-RUBY.strip_indent)
        ['a@example.com', 'b@example.com']
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `%w` or `%W` for an array of words.
      RUBY
    end

    it 'auto-corrects an array of email addresses' do
      new_source = autocorrect_source("['a@example.com', 'b@example.com']")
      expect(new_source).to eq('%w(a@example.com b@example.com)')
    end
  end

  context 'when the WordRegex configuration is not a Regexp' do
    let(:cop_config) { { 'WordRegex' => 'just_a_string' } }

    it 'still parses the code without raising an error' do
      expect { inspect_source('') }.not_to raise_error
    end
  end

  context 'with a WordRegex configuration which accepts almost anything' do
    let(:cop_config) { { 'MinSize' => 0, 'WordRegex' => /\S+/ } }

    it 'uses %W when autocorrecting strings with non-printable chars' do
      new_source = autocorrect_source('["\x1f\x1e", "hello"]')
      expect(new_source).to eq('%W(\u001F\u001E hello)')
    end

    it 'uses %w for strings which only appear to have an escape' do
      new_source = autocorrect_source("['hi\\tthere', 'again\\n']")
      expect(new_source).to eq('%w(hi\\tthere again\\n)')
    end
  end

  context 'with a treacherous WordRegex configuration' do
    let(:cop_config) { { 'MinSize' => 0, 'WordRegex' => /[\w \[\]\(\)]/ } }

    it "doesn't break when words contain whitespace" do
      new_source = autocorrect_source("['hi there', 'something\telse']")
      expect(new_source).to eq("['hi there', 'something\telse']")
    end

    it "doesn't break when words contain delimiters" do
      new_source = autocorrect_source("[')', ']', '(']")
      expect(new_source).to eq('%w(\\) ] \\()')
    end

    context 'when PreferredDelimiters is specified' do
      let(:other_cops) do
        {
          'Style/PercentLiteralDelimiters' => {
            'PreferredDelimiters' => {
              'default' => '[]'
            }
          }
        }
      end

      it 'autocorrects an array with delimiters' do
        new_source = autocorrect_source("[')', ']', '(', '[']")
        expect(new_source).to eq('%w[) \\] ( \\[]')
      end
    end
  end
end
