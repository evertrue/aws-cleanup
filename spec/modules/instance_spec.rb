require 'spec_helper'
require 'modules/instances'

describe InstancesCleanup do
  let(:ic) { InstancesCleanup.new }

  before { allow(Aws::EC2::Client).to receive(:new).and_return object_double :ec2_connection }

  describe '.cleanup_instances' do
    context 'No expired instances' do
      before { allow(ic).to receive(:expired_instances_ids).and_return([]) }

      it 'prints "No instances to clean up"' do
        expect(ic).to receive(:puts).with 'No instances to clean up'
        ic.cleanup_instances
      end
    end

    context '2 expired instances' do
      before do
        allow(ic).to receive(:expired_instances_ids).and_return(%w(
          i-0000000000000000
          i-0000000000000001
        ))
      end

      it 'does not print "No instances to clean up"' do
        allow(ic).to receive_message_chain :ec2, :terminate_instances
        expect(ic).to_not receive(:puts).with 'No instances to clean up'
        ic.cleanup_instances
      end

      it 'prints "Deleting instances: i-0000000000000000, i-0000000000000001"' do
        allow(ic).to receive_message_chain :ec2, :terminate_instances
        expect(ic).to receive(:puts).with(
          'Deleting instances: i-0000000000000000, i-0000000000000001'
        )
        ic.cleanup_instances
      end

      it 'Deletes 2 instances called "i-0000000000000000" and "i-0000000000000001"' do
        expect(ic).to(
          receive_message_chain(:ec2, :terminate_instances).with instance_ids: %w(
            i-0000000000000000 i-0000000000000001
          )
        )
        ic.cleanup_instances
      end
    end

    context '20 expired instances' do
      let(:array_of_iids) { (10..30).to_a.map { |n| 'i-00000000000000' + n.to_s } }

      before do
        allow(ic).to receive(:expired_instances_ids).and_return array_of_iids
      end

      it 'calls prompt_user! with iids' do
        expect(ic).to receive(:prompt_user!).with array_of_iids
        allow(ic).to receive_message_chain(:ec2, :terminate_instances)
        ic.cleanup_instances
      end

      it 'does not print "No instances to clean up"' do
        allow(ic).to receive(:prompt_user!)
        allow(ic).to receive_message_chain(:ec2, :terminate_instances)
        expect(ic).to_not receive(:puts).with 'No instances to clean up'
        ic.cleanup_instances
      end

      # Can't test disapproval because that just bails
      context 'user approves' do
        before { allow(ic).to receive(:prompt_user!).and_return true }

        it('prints "Deleting instances:" with a list') do
          allow(ic).to receive_message_chain :ec2, :terminate_instances
          expect(ic).to receive(:puts).with 'Deleting instances: ' + array_of_iids.join(', ')
          ic.cleanup_instances
        end

        it 'Deletes all 20 instances' do
          expect(ic).to(
            receive_message_chain(:ec2, :terminate_instances).with instance_ids: array_of_iids
          )
          ic.cleanup_instances
        end
      end
    end
  end

  describe '.prompt_user!' do
    it 'print a warning' do
      allow(ic).to receive(:gets).and_return("yes\n")
      expect(ic).to receive(:puts).with(
        'WARNING: The following 2 instances will be terminated: i-0000000000000000, ' \
        'i-0000000000000001'
      )
      ic.send :prompt_user!, %w(i-0000000000000000 i-0000000000000001)
    end

    context 'user approves' do
      before { allow(ic).to receive(:gets).and_return("yes\n") }

      it 'return false' do
        expect(ic.send :prompt_user!, []).to be_nil
      end
    end

    context 'user does not approve' do
      before { allow(ic).to receive(:gets).and_return("no\n") }

      it 'raise SystemExit' do
        expect { ic.send :prompt_user!, [] }.to raise_error SystemExit
      end
    end
  end

  describe '.expired_instances_ids' do
    it 'return instance ids' do
      allow(ic).to receive(:expired_instances).and_return([
        object_double('instance', instance_id: 'i-0000000000000000'),
        object_double('instance', instance_id: 'i-0000000000000001')
      ])
      expect(ic.send :expired_instances_ids).to eq %w(i-0000000000000000 i-0000000000000001)
    end
  end

  describe '.expired_instances' do
    it 'return a mix of test and tag instances without duplicates' do
      test_instances = [object_double('instance0', instance_id: 'i-0000000000000000')]
      both = [object_double('instance1', instance_id: 'i-0000000000000001')]
      tag_instances = [object_double('instance2', instance_id: 'i-0000000000000002')]

      allow(ic).to receive(:expired_test_instances).and_return(test_instances + both)
      allow(ic).to receive(:instances_expired_by_tag).and_return(both + tag_instances)

      expect(ic.send :expired_instances).to eq(test_instances + both + tag_instances)
    end
  end

  describe '.expired_test_instances' do
    let(:time) { Time.parse('2017-05-12 11:56:49 -0400') }
    let(:time_one_hour_ago) { Time.parse('2017-05-12 11:56:49 -0400') - 86_401 }
    let(:expired_instance) { object_double('expired_instance', launch_time: time_one_hour_ago) }
    let(:unexpired_instance) { object_double('unexpired_instance', launch_time: time) }

    before do
      allow(ic).to receive(:test_instances).and_return [expired_instance, unexpired_instance]
      allow(ic).to receive(:expired_age?).with(86_400, time).and_return false # not expired
      allow(ic).to receive(:expired_age?).with(86_400, time_one_hour_ago).and_return true # expired
    end

    it 'return only the expired instance' do
      expect(ic.send :expired_test_instances).to eq [expired_instance]
    end
  end

  describe '.test_instances' do
    let(:test_security_group_name_instance) do
      object_double(
        'test_security_group_name_instance',
        security_groups: [
          object_double('security_group', group_name: 'ci-testing', group_id: 'sg-1e804874')
        ]
      )
    end
    let(:test_security_group_id_instance) do
      object_double(
        'test_security_group_id_instance',
        security_groups: [
          object_double('security_group', group_name: 'ci-testing', group_id: 'sg-1e804874')
        ]
      )
    end
    let(:test_tag_instance) do
      object_double(
        'test_tag_instance',
        security_groups: [
          object_double('security_group', group_name: 'default', group_id: 'sg-00000000')
        ],
        tags: [object_double('tag', key: 'Type', value: 'test')]
      )
    end
    let(:non_test_instance) do
      object_double(
        'non_test_instance',
        security_groups: [
          object_double('security_group', group_name: 'default', group_id: 'sg-00000000')
        ],
        tags: [object_double('tag', key: 'Type', value: 'default')]
      )
    end

    it 'only return test instances' do
      allow(ic).to receive(:instances).and_return [
        test_security_group_name_instance,
        test_security_group_id_instance,
        test_tag_instance,
        non_test_instance
      ]
      expect(ic.send :test_instances).to eq [
        test_security_group_name_instance,
        test_security_group_id_instance,
        test_tag_instance
      ]
    end
  end

  describe '.instances_expired_by_tag' do
    let(:time_one_day_ago) { Time.parse('2017-05-12 11:56:49 -0400') - 86_401 }
    let(:time_now) { Time.now }
    let(:expire_after_instance) do
      object_double(
        'expire_after_instance',
        launch_time: time_one_day_ago,
        tags: [object_double('tag', key: 'expire_after', value: 3600)]
      )
    end
    let(:expired_instance) do
      object_double(
        'expired_instance',
        tags: [object_double('tag', key: 'expires', value: time_one_day_ago.to_s)]
      )
    end
    let(:unexpired_instance1) do
      object_double(
        'unexpired_instance1',
        tags: [object_double('tag', key: 'expires', value: (time_now + 3600).to_s)]
      )
    end
    let(:unexpired_instance2) do
      object_double(
        'unexpired_instance2',
        launch_time: time_now,
        tags: [object_double('tag', key: 'expire_after', value: 3600)]
      )
    end

    it 'return only expired instances (stubbed method version)' do
      allow(ic).to receive(:instances).and_return [
        expire_after_instance,
        expired_instance,
        unexpired_instance1,
        unexpired_instance2
      ]
      allow(ic).to receive(:expired_age?).with(3600, time_one_day_ago).and_return true
      allow(ic).to receive(:expired_time?).with(time_one_day_ago.to_s).and_return true
      allow(ic).to receive(:expired_time?).with((time_now + 3600).to_s).and_return false
      allow(ic).to receive(:expired_age?).with(3600, time_now).and_return false

      expect(ic.send :instances_expired_by_tag).to eq [expire_after_instance, expired_instance]
    end

    it 'return only expired instances' do
      allow(ic).to receive(:instances).and_return [
        expire_after_instance,
        expired_instance,
        unexpired_instance1,
        unexpired_instance2
      ]

      expect(ic.send :instances_expired_by_tag).to eq [expire_after_instance, expired_instance]
    end
  end

  describe '.expired_age?' do
    context 'expired' do
      it 'return true' do
        expect(ic.send :expired_age?, 100, Time.now - 3600).to eq true
      end
    end
    context 'unexpired' do
      it 'return false' do
        expect(ic.send :expired_age?, 100, Time.now - 30).to eq false
      end
    end
  end

  describe '.expired_time?' do
    context 'expired' do
      it 'return true' do
        expect(ic.send :expired_time?, (Time.now - 100).to_s).to eq true
      end
    end
    context 'unexpired' do
      it 'return false' do
        expect(ic.send :expired_time?, (Time.now + 100).to_s).to eq false
      end
    end
  end
end
