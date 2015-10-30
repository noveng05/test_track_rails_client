require 'rails_helper'

RSpec.describe TestTrackRails::Visitor do
  let(:new_visitor) { described_class.new }
  let(:existing_visitor) { described_class.new(id: existing_visitor_id) }
  let(:existing_visitor_id) { "00000000-0000-0000-0000-000000000000" }
  let(:assignment_registry) { { 'blue_button' => 'true', 'time' => 'waits_for_no_man' } }
  let(:split_registry) do
    {
      'blue_button' => {
        'false' => 50,
        'true' => 50
      },
      'quagmire' => {
        'untenable' => 50,
        'manageable' => 50
      },
      'time' => {
        'hammertime' => 100,
        'clobberin_time' => 0
      }
    }
  end

  before do
    allow(TestTrackRails::AssignmentRegistry).to receive(:for_visitor).and_call_original
    allow(TestTrackRails::AssignmentRegistry).to receive(:fake_instance_attributes).and_return(assignment_registry)
    allow(TestTrackRails::SplitRegistry).to receive(:to_hash).and_return(split_registry)
  end

  it "preserves a passed ID" do
    expect(existing_visitor.id).to eq existing_visitor_id
  end

  it "generates its own UUID otherwise" do
    allow(SecureRandom).to receive(:uuid).and_return("fake uuid")
    expect(new_visitor.id).to eq "fake uuid"
  end

  describe "#assignment_registry" do
    it "doesn't request the registry for a newly-generated visitor" do
      expect(new_visitor.assignment_registry).to eq({})
      expect(TestTrackRails::AssignmentRegistry).not_to have_received(:for_visitor)
    end

    it "returns the server-provided assignments for an existing visitor" do
      expect(existing_visitor.assignment_registry).to eq assignment_registry
    end
  end

  describe "#vary" do
    let(:blue_block) { -> { '.blue' } }
    let(:red_block) { -> { '.red' } }

    before do
      allow(TestTrackRails::VariantCalculator).to receive(:new).and_return(double(variant: 'manageable'))
    end

    context "new_visitor" do
      def vary_quagmire_split
        new_visitor.vary(:quagmire) do |v|
          v.when :untenable do
            raise "this branch shouldn't be executed, buddy"
          end
          v.default :manageable do
            "#winning"
          end
        end
      end

      it "asks the VariantCalculator for an assignment" do
        expect(vary_quagmire_split).to eq "#winning"
        expect(TestTrackRails::VariantCalculator).to have_received(:new).with(visitor: new_visitor, split_name: 'quagmire')
      end

      it "updates #new_assignments with assignment" do
        expect(vary_quagmire_split).to eq "#winning"
        expect(new_visitor.new_assignments['quagmire']).to eq 'manageable'
      end
    end

    context "existing_visitor" do
      def vary_blue_button_split
        existing_visitor.vary :blue_button do |v|
          v.when :true, &blue_block
          v.default :false, &red_block
        end
      end

      def vary_time_split
        existing_visitor.vary :time do |v|
          v.when :clobberin_time do
            "Fantastic Four IV: The Fantasticing"
          end
          v.default :hammertime do
            "can't touch this"
          end
        end
      end

      it "pulls previous assignment from registry" do
        expect(vary_blue_button_split).to eq ".blue"
        expect(TestTrackRails::VariantCalculator).not_to have_received(:new)

        expect(existing_visitor.new_assignments).not_to have_key('blue_button')
      end

      it "creates new assignment for unimplemented previous assignment" do
        expect(existing_visitor.assignment_registry['time']).to eq 'waits_for_no_man'

        expect(vary_time_split).to eq "can't touch this"
        expect(TestTrackRails::VariantCalculator).not_to have_received(:new)

        expect(existing_visitor.new_assignments['time']).to eq 'hammertime'
      end
    end

    context "structure" do
      it "must be given a block" do
        expect { new_visitor.vary(:blue_button) }.to raise_error("must provide block to `vary` for blue_button")
      end

      it "requires less than two defaults" do
        expect do
          new_visitor.vary(:blue_button) do |v|
            v.when :true, &blue_block
            v.default :false, &red_block
            v.default :false, &red_block
          end
        end.to raise_error("cannot provide more than one `default`")
      end

      it "requires more than zero defaults" do
        expect { new_visitor.vary(:blue_button) { |v| v.when(:true, &blue_block) } }.to raise_error("must provide exactly one `default`")
      end

      it "requires at least one when" do
        expect do
          new_visitor.vary(:blue_button) do |v|
            v.default :true, &red_block
          end
        end.to raise_error("must provide at least one `when`")
      end
    end
  end

  describe "#split_registry" do
    it "memoizes the global SplitRegistry hash" do
      2.times { existing_visitor.split_registry }
      expect(TestTrackRails::SplitRegistry).to have_received(:to_hash).exactly(:once)
    end
  end

  describe "#log_in!" do
    let(:delayed_identifier_proxy) { double(create!: "fake visitor") }

    before do
      allow(TestTrackRails::Identifier).to receive(:delay).and_return(delayed_identifier_proxy)
    end

    it "sends the appropriate params to test track" do
      allow(TestTrackRails::Identifier).to receive(:create!).and_call_original
      existing_visitor.log_in!('bettermentdb_user_id', 444)
      expect(TestTrackRails::Identifier).to have_received(:create!).with(
        identifier_type: 'bettermentdb_user_id',
        visitor_id: existing_visitor_id,
        value: "444"
      )
    end

    it "preserves id if unchanged" do
      expect(existing_visitor.log_in!('bettermentdb_user_id', 444).id).to eq existing_visitor_id
    end

    it "delays the identifier creation if TestTrack times out and carries on" do
      allow(TestTrackRails::Identifier).to receive(:create!) { raise(Faraday::TimeoutError, "You snooze you lose!") }

      expect(existing_visitor.log_in!('bettermentdb_user_id', 444).id).to eq existing_visitor_id

      expect(delayed_identifier_proxy).to have_received(:create!).with(
        identifier_type: 'bettermentdb_user_id',
        visitor_id: existing_visitor_id,
        value: "444"
      )
    end

    it "normally doesn't delay identifier creation" do
      expect(existing_visitor.log_in!('bettermentdb_user_id', 444).id).to eq existing_visitor_id

      expect(delayed_identifier_proxy).not_to have_received(:create!)
    end

    context "with stubbed identifier creation" do
      let(:identifier) { TestTrackRails::Identifier.new(visitor: { id: "server_id", assignment_registry: server_registry }) }
      let(:server_registry) { { "foo" => "definitely", "bar" => "occasionally" } }

      before do
        allow(TestTrackRails::Identifier).to receive(:create!).and_return(identifier)
      end

      it "changes id if changed" do
        expect(existing_visitor.log_in!('bettermentdb_user_id', 444).id).to eq 'server_id'
      end

      it "ingests a server-provided assignment as non-new" do
        existing_visitor.log_in!('bettermentdb_user_id', 444)

        expect(existing_visitor.assignment_registry['foo']).to eq 'definitely'
        expect(existing_visitor.new_assignments).not_to have_key 'foo'
      end

      it "preserves a local new assignment with no conflicting server-provided assignment as new" do
        existing_visitor.new_assignments['baz'] = existing_visitor.assignment_registry['baz'] = 'never'

        existing_visitor.log_in!('bettermentdb_user_id', 444)

        expect(existing_visitor.assignment_registry['baz']).to eq 'never'
        expect(existing_visitor.new_assignments['baz']).to eq 'never'
      end

      it "removes and overrides a local new assignment with a conflicting server-provided assignment" do
        existing_visitor.new_assignments['foo'] = existing_visitor.assignment_registry['foo'] = 'something_else'

        existing_visitor.log_in!('bettermentdb_user_id', 444)

        expect(existing_visitor.assignment_registry['foo']).to eq 'definitely'
        expect(existing_visitor.new_assignments).not_to have_key 'foo'
      end

      it "overrides a local existing assignment with a conflicting server-provided assignment" do
        existing_visitor.assignment_registry['foo'] = 'something_else'

        existing_visitor.log_in!('bettermentdb_user_id', 444)

        expect(existing_visitor.assignment_registry['foo']).to eq 'definitely'
        expect(existing_visitor.new_assignments).not_to have_key 'foo'
      end
    end
  end
end
