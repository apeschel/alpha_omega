require 'alpha_omega/deploy/strategy/remote'

module Capistrano
  module Deploy
    module Strategy

      # Implements the deployment strategy which does an SCM checkout on each
      # target host. This is the default deployment strategy for Capistrano.
      class Checkout < Remote
        protected

          # Returns the SCM's checkout command for the revision to deploy.
          def commands
            @commands ||= source.checkout(revision, configuration[:deploy_release])
          end
      end

    end
  end
end
