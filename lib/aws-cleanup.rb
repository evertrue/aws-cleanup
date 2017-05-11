require 'aws-cleanup/version'
require 'aws-sdk'

class AwsCleanup
  TEST_INSTANCE_EXPIRE_AGE = (3_600 * 24).freeze
  TEST_GROUP_ID = 'sg-1e804874'.freeze
  TEST_GROUP_NAME = 'ci-testing'.freeze

  def self.run(resource)
    AwsCleanup.new.run resource
  end

  def run(resource = nil)
    if resource
      require "#{resource}-cleanup"
      AwsCleanup.const_get("#{resource.capitalize}Cleanup").run
      return
    end

    Dir.glob(File.dirname(File.absolute_path __FILE__) + '/modules/*').each do |resource_file|
      require resource_file
      class_name = "#{File.basename(resource_file).sub('.rb', '').capitalize}Cleanup"
      AwsCleanup.const_get(class_name).run
    end
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
