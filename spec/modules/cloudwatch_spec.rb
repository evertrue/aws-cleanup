require 'spec_helper'
require 'modules/cloudwatch'

describe CloudwatchCleanup do
  let(:cwc) do
    CloudwatchCleanup.new
  end

  before do
    allow(Aws::CloudWatch::Client).to receive(:new).and_return object_double :cloudwatch_connection
  end

  describe '.cleaup_alarms' do
    context 'No alarms' do
      before { allow(cwc).to receive(:orphaned_alarms).and_return([]) }

      it 'prints "No alarms to clean up"' do
        expect(cwc).to receive(:puts).with 'No alarms to clean up'
        cwc.cleanup_alarms
      end
    end

    context '2 alarms' do
      before do
        allow(cwc).to receive(:orphaned_alarms).and_return([
          object_double('cloudwatch_alarm', alarm_name: 'alarm1'),
          object_double('cloudwatch_alarm', alarm_name: 'alarm2')
        ])
      end

      it 'does not print "No alarms to clean up"' do
        allow(cwc).to receive_message_chain :cloudwatch, :delete_alarms
        expect(cwc).to_not receive(:puts).with 'No alarms to clean up'
        cwc.cleanup_alarms
      end

      it 'prints "Deleting alarms: alarm1, alarm2"' do
        allow(cwc).to receive_message_chain :cloudwatch, :delete_alarms
        expect(cwc).to receive(:puts).with 'Deleting alarms: alarm1, alarm2'
        cwc.cleanup_alarms
      end

      it 'Deletes 2 alarms called "alarm1" and "alarm2"' do
        expect(cwc).to(
          receive_message_chain(:cloudwatch, :delete_alarms).with alarm_names: %w(alarm1 alarm2)
        )
        cwc.cleanup_alarms
      end
    end
  end

  describe '.orphaned_alarms' do
    context 'No alarms with insufficient data' do
      before { allow(cwc).to receive(:insufficient_data_alarms).and_return [] }

      it('return empty array') { expect(cwc.send :orphaned_alarms).to eq [] }
    end

    context '1 alarm with insufficient data' do
      context 'but no dimensions' do
        before do
          allow(cwc).to receive(:insufficient_data_alarms).and_return [
            object_double('alarm', dimensions: [])
          ]
        end

        it('return empty array') { expect(cwc.send :orphaned_alarms).to eq [] }
      end

      context '1 dimension in use' do
        before do
          allow(cwc).to receive(:insufficient_data_alarms).and_return [
            object_double('alarm', dimensions: %i(some_dimension))
          ]
        end

        it 'call dimension_in_use?' do
          expect(cwc).to receive(:dimension_in_use?).with(:some_dimension).and_return true
          cwc.send :orphaned_alarms
        end

        it 'return empty array' do
          allow(cwc).to receive(:dimension_in_use?).with(:some_dimension).and_return true
          expect(cwc.send :orphaned_alarms).to eq []
        end
      end

      context '1 dimension NOT in use' do
        let(:alarm_in_use) { object_double('alarm', dimensions: %i(some_dimension)) }

        before { allow(cwc).to receive(:insufficient_data_alarms).and_return [alarm_in_use] }

        it 'return the alarm that\'s in use' do
          allow(cwc).to receive(:dimension_in_use?).with(:some_dimension).and_return false
          expect(cwc.send :orphaned_alarms).to eq [alarm_in_use]
        end
      end
    end
  end

  describe '.dimension_in_use?' do
    context 'InstanceId' do
      let(:dimension) do
        object_double(
          'dimension',
          name: 'InstanceId',
          value: 'i-0000000000000000'
        )
      end

      context 'in use' do
        before { allow(cwc).to receive(:instance_ids).and_return %w(i-0000000000000000) }

        it('return true') { expect(cwc.send :dimension_in_use?, dimension).to eq true }
      end

      context 'not in use' do
        before { allow(cwc).to receive(:instance_ids).and_return [] }

        it('return false') { expect(cwc.send :dimension_in_use?, dimension).to eq false }
      end
    end

    context 'QueueName' do
      let(:dimension) do
        object_double(
          'dimension',
          name: 'QueueName',
          value: 'my_sqs_queue'
        )
      end

      context 'in use' do
        before { allow(cwc).to receive(:queue_names).and_return %w(my_sqs_queue) }

        it('return true') { expect(cwc.send :dimension_in_use?, dimension).to eq true }
      end

      context 'not in use' do
        before { allow(cwc).to receive(:queue_names).and_return [] }

        it('return false') { expect(cwc.send :dimension_in_use?, dimension).to eq false }
      end
    end

    context 'DBInstanceIdentifier' do
      let(:dimension) do
        object_double(
          'dimension',
          name: 'DBInstanceIdentifier',
          value: 'my_rds_db'
        )
      end

      context 'in use' do
        before { allow(cwc).to receive(:db_names).and_return %w(my_rds_db) }

        it('return true') { expect(cwc.send :dimension_in_use?, dimension).to eq true }
      end

      context 'not in use' do
        before { allow(cwc).to receive(:db_names).and_return [] }

        it('return false') { expect(cwc.send :dimension_in_use?, dimension).to eq false }
      end
    end

    context 'Some other [unsupported] dimension' do
      let(:dimension) { object_double 'dimension', name: 'OtherDimension' }

      it 'prints a helpful message' do
        expect(cwc).to receive(:puts).with 'Unsupported dimension: OtherDimension'
        cwc.send :dimension_in_use?, dimension
      end

      it('return true') { expect(cwc.send :dimension_in_use?, dimension).to eq true }
    end
  end
end
