require 'aws-cleanup/version'
require 'aws-sdk'
require 'cloudwatch-cleanup'
require 'instances-cleanup'

class AwsCleanup
  TEST_INSTANCE_EXPIRE_AGE = (3_600 * 24).freeze
  TEST_GROUP_ID = 'sg-1e804874'.freeze
  TEST_GROUP_NAME = 'ci-testing'.freeze

  def self.run
    AwsCleanup.new.run
  end

  def run
    InstancesCleanup.run
    CloudWatchCleanup.run
  end

  private

  def instance_ids
    instances.map(&:instance_id)
  end

  def instances
    @instances ||=
      ec2.describe_instances(
        filters: [{ name: 'instance-state-name', values: ['running'] }]
      ).reservations.map(&:instances).flatten
  end

  def ec2
    @ec2 ||= Aws::EC2::Client.new
  end
end
