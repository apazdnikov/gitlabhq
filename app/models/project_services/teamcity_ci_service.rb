# Base class for CI services
# List methods you need to implement to get your CI service
# working with GitLab Merge Requests

require 'teamcity'

class TeamcityCiService < CiService
  attr_accessible :project_url
  attr_accessible :subdomain

  validates :project_url, presence: true, if: :activated?
  validates :subdomain, presence: true, if: :activated?
  validates :api_key, presence: true, if: :activated?

  # Return complete url to build page
  #
  # Ex.
  #   http://jenkins.example.com:8888/job/test1/scm/bySHA1/12d65c
  #
  def build_page(sha, branch)
    b = find_build_id_by_sha sha, branch

    return 'http://error' unless b

    b.webUrl
  end

  # Return string with build status or :error symbol
  #
  # Allowed states: 'success', 'failed', 'running', 'pending'
  #
  #
  # Ex.
  #   @service.commit_status('13be4ac')
  #   # => 'success'
  #
  #   @service.commit_status('2abe4ac')
  #   # => 'running'
  #
  #

  def commit_status(sha, branch)
    convert_state_teamcity_to_gitlab(find_build_id_by_sha(sha, branch))
  end

  def title
    'Teamcity CI'
  end

  def description
    'Continuous integration server from Teamcity'
  end

  def to_param
    'teamcity_ci'
  end

  def fields
    [
      { type: 'text', name: 'project_url', placeholder: 'https://teamcity.example.com' },
      { type: 'text', name: 'subdomain', placeholder: 'Build Configuration Id' },
      { type: 'text', name: 'api_key', placeholder: 'teamcity_user:teamcity_password' },
    ]
  end

  def execute(_push_data)
  end

  def can_test?
    false
  end

  private

  def find_build_id_by_sha(sha, branch)
    if branch
      return my_find_build_id_by_sha(sha, "refs/heads/#{branch}") || my_find_build_id_by_sha(sha, "#{branch}")
    else
      return my_find_build_id_by_sha sha, '(branched:any)'
    end
  end

  def my_find_build_id_by_sha(sha, branch)
    user, password = api_key.split(':')
    tc = TeamCity.client(endpoint: "#{project_url}/httpAuth/app/rest", http_user: user, http_password: password)
    builds = tc.builds(buildType: subdomain, branch: branch, running: 'any', canceled: 'any')

    return nil unless builds

    builds.each do |b|
      info = tc.build(id: b.id)
      info.revisions.revision.each do |r|
        if r.version == sha
          return info
        end
      end
    end

    nil
  end

  STATES = { 'success' => 'success',
             'failure' => 'failed',
             'running' => 'running' }

  def convert_state_teamcity_to_gitlab(build_info)
    return :pending unless build_info
    return :running if build_info.state == 'running'

    if build_info.state == 'finished'
      if STATES.has_key?(build_info.status.downcase)
        return STATES[build_info.status.downcase]
      end
    end

    Gitlab::AppLogger.info "teamcity build_info.state = #{build_info.state} not supported, suppose it failed"

    :failed
  end
end
