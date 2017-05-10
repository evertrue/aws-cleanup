require 'aws-cleanup/version'
require 'aws-sdk'

class AwsCleanup
  TEST_INSTANCE_EXPIRE_AGE = (3_600 * 24).freeze
  TEST_GROUP_ID = 'sg-1e804874'.freeze
  TEST_GROUP_NAME = 'ci-testing'.freeze

  def self.run
    AwsCleanup.new.run
  end

  def run
    cleanup_instances
    cleaup_alarms
  end

  private

  def cleanup_instances
    eii = expired_instances_ids
    return unless eii.any?
    puts 'Deleting instances: ' + eii.join(', ')
    ec2.terminate_instances instance_ids: eii
  end

  def cleaup_alarms
    oa = orphaned_alarms.map(&:alarm_name)
    return unless oa.any?
    puts 'Deleting alarms: ' + oa.join(', ')
    cloudwatch.delete_alarms alarm_names: oa
  end

  def orphaned_alarms
    insufficient_data_alarms.select do |alarm|
      alarm.dimensions.any? &&
        !alarm.dimensions.find { |dimension| dimension_in_use? dimension }
    end
  end

  def dimension_in_use?(dimension)
    case dimension.name
    when 'InstanceId'
      instance_ids.include? dimension.value
    when 'QueueName'
      queue_names.include? dimension.value
    when 'DBInstanceIdentifier'
      db_names.include? dimension.value
    else
      puts "Unsupported dimension: #{dimension.name}"
      true
    end
  end

  def queue_names
    @queue_names ||= sqs.list_queues.queue_urls.map { |q| URI(q).path.split('/')[2..-1].join('/') }
  end

  def db_names
    @db_names ||= rds.describe_db_instances.db_instances.map(&:db_instance_identifier)
  end

  def expired_instances_ids
    expired_instances.map(&:instance_id)
  end

  def expired_instances
    expired_test_instances | instances_expired_by_tag
  end

  def expired_test_instances
    test_instances.select { |instance| expired_age? TEST_INSTANCE_EXPIRE_AGE, instance.launch_time }
  end

  def test_instances
    instances.select do |instance|
      instance.security_groups.find do |sg|
        sg.group_name == TEST_GROUP_NAME || sg.group_id == TEST_GROUP_ID
      end ||
        instance.tags.find { |t| t.key == 'Type' && t.value == 'test' }
    end
  end

  def instances_expired_by_tag
    instances.select do |instance|
      instance.tags.find do |t|
        (t.key == 'expire_after' && expired_age?(t.value, instance.launch_time)) ||
          (t.key == 'expires' && expired_time?(t.value))
      end
    end
  end

  def expired_age?(secs, launch_time)
    Time.now > (launch_time + secs)
  end

  def expired_time?(timestamp)
    # `timestamp` should be a string in this format:
    # 2017-05-10 13:04:01 -0400
    Time.now > Time.parse(timestamp)
  end

  def instance_ids
    instances.map(&:instance_id)
  end

  def instances
    @instances ||=
      ec2.describe_instances(
        filters: [{ name: 'instance-state-name', values: ['running'] }]
      ).reservations.map(&:instances).flatten
  end

  def insufficient_data_alarms
    cloudwatch.describe_alarms(state_value: 'INSUFFICIENT_DATA').metric_alarms
  end

  def cloudwatch
    @cloudwatch ||= Aws::CloudWatch::Client.new
  end

  def ec2
    @ec2 ||= Aws::EC2::Client.new
  end

  def sqs
    @sqs ||= Aws::SQS::Client.new
  end

  def rds
    @rds ||= Aws::RDS::Client.new
  end
end
