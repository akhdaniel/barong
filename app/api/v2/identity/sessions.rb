# frozen_string_literal: true

require_dependency 'barong/jwt'

module API::V2
  module Identity
    class Sessions < Grape::API
      helpers do
        def get_user(email)
          user = User.find_by(email: email)
          error!({ errors: ['identity.session.invalid_params'] }, 401) unless user

          if user.state == 'banned'
            login_error!(reason: 'Your account is banned', error_code: 401,
                         user: user.id, action: 'login', result: 'failed', error_text: 'banned')
          end

          if user.state == 'deleted'
            login_error!(reason: 'Your account is deleted', error_code: 401,
                         user: user.id, action: 'login', result: 'failed', error_text: 'deleted')
          end

          # if user is not active or pending, then return 401
          unless user.state.in?(%w[active pending])
            login_error!(reason: 'Your account is not active', error_code: 401,
                         user: user.id, action: 'login', result: 'failed', error_text: 'not_active')
          end
          user
        end
      end

      desc 'Session related routes'
      resource :sessions do
        desc 'Start a new session',
             failure: [
               { code: 400, message: 'Required params are empty' },
               { code: 404, message: 'Record is not found' }
             ]
        params do
          requires :email
          requires :password
          optional :captcha_response,
                   types: { value: [String, Hash], message: 'identity.session.invalid_captcha_format' },
                   desc: 'Response from captcha widget'
          optional :otp_code,
                   type: String,
                   desc: 'Code from Google Authenticator'
        end
        post do
          verify_captcha!(response: params['captcha_response'], endpoint: 'session_create')

          declared_params = declared(params, include_missing: false)
          user = get_user(declared_params[:email])

          unless user.authenticate(declared_params[:password])
            login_error!(reason: 'Invalid Email or Password', error_code: 401, user: user.id,
                         action: 'login', result: 'failed', error_text: 'invalid_params')
          end

          unless user.otp
            activity_record(user: user.id, action: 'login', result: 'succeed', topic: 'session')
            csrf_token = open_session(user)
            publish_session_create(user)

            present user, with: API::V2::Entities::UserWithFullInfo, csrf_token: csrf_token
            return status 200
          end

          error!({ errors: ['identity.session.missing_otp'] }, 401) if declared_params[:otp_code].blank?
          unless TOTPService.validate?(user.uid, declared_params[:otp_code])
            login_error!(reason: 'OTP code is invalid', error_code: 403,
                         user: user.id, action: 'login::2fa', result: 'failed', error_text: 'invalid_otp')
          end

          activity_record(user: user.id, action: 'login::2fa', result: 'succeed', topic: 'session')
          csrf_token = open_session(user)
          publish_session_create(user)

          present user, with: API::V2::Entities::UserWithFullInfo, csrf_token: csrf_token
          status(200)
        end

        desc 'Destroy current session',
          failure: [
            { code: 400, message: 'Required params are empty' },
            { code: 404, message: 'Record is not found' }
          ],
          success: { code: 200, message: 'Session was destroyed' }
        delete do
          user = User.find_by(uid: session[:uid])
          error!({ errors: ['identity.session.not_found'] }, 404) unless user

          activity_record(user: user.id, action: 'logout', result: 'succeed', topic: 'session')

          Barong::RedisSession.delete(user.uid, session.id)
          session.destroy

          status(200)
        end

        desc 'Auth0 authentication by id_token',
             success: { code: 200, message: 'User authenticated' },
             failure: [
               { code: 400, message: 'Required params are empty' },
               { code: 404, message: 'Record is not found' }
             ]
        params do
          requires :id_token,
                   type: String,
                   allow_blank: false,
                   desc: 'ID Token'
        end
        post '/auth0' do
          begin
            # Decode ID token to get user info
            claims = Barong::Auth0::JWT.verify(params[:id_token]).first
            error!({ errors: ['identity.session.auth0.invalid_params'] }, 401) unless claims.key?('email')
            user = User.find_by(email: claims['email'])

            # If there is no user in platform and user email verified from id_token
            # system will create user
            if user.blank? && claims['email_verified']
              user = User.create!(email: claims['email'], state: 'active')
              user.labels.create!(scope: 'private', key: 'email', value: 'verified')
            elsif claims['email_verified'] == false
              error!({ errors: ['identity.session.auth0.invalid_params'] }, 401) unless user
            end

            activity_record(user: user.id, action: 'login', result: 'succeed', topic: 'session')
            csrf_token = open_session(user)
            publish_session_create(user)

            present user, with: API::V2::Entities::UserWithFullInfo, csrf_token: csrf_token
          rescue StandardError => e
            report_exception(e)
            error!({ errors: ['identity.session.auth0.invalid_params'] }, 422)
          end
        end

        namespace :switch do
          desc 'Switch user session',
               success: { code: 200, message: 'Session was switched' },
               failure: [
                 { code: 400, message: 'Required params are missing' },
                 { code: 422, message: 'Validation errors' }
               ]
          params do
            requires :aid,
                     type: String,
                     allow_blank: false,
                     desc: 'Organization account id'
          end
          post do
            user = User.find_by(uid: session[:uid])
            error!({ errors: ['identity.session.not_found'] }, 404) unless user

            # Check user in the organization
            aid = params[:aid]
            account = Membership.joins(:organization)
                                .where(organizations: { oid: aid }, user_id: user.id)
                                .select('memberships.*,organizations.organization_id').first
            error!({ errors: ['identity.member.not_found'] }, 404) unless account

            # Set oid as aid for default case of switched as organization admin
            oid = aid
            unless account.organization_id.nil?
              organization = Organization.find(account.organization_id)
              error!({ errors: ['identity.organization.not_found'] }, 404) unless organization

              # Set oid as sub-organization in case of switched as organization account
              oid = organization.oid
            end

            activity_record(user: user.id, action: 'switch::orgnization', result: 'succeed', topic: 'session')

            Barong::RedisSession.delete(user.uid, session.id)
            session.destroy

            switch = {
              oid: oid,
              aid: aid,
              account_role: account.role
            }
            csrf_token = open_switch_session(user, switch)
            publish_session_switch(user, switch)

            present user, with: API::V2::Entities::UserWithFullInfo, csrf_token: csrf_token
            status(200)
          end

          desc 'Destroy switched session',
             failure: [
               { code: 404, message: 'Record is not found' }
             ],
             success: { code: 200, message: 'Switched was destroyed' }
          delete do
            user = User.find_by(uid: session[:uid])
            error!({ errors: ['identity.session.not_found'] }, 404) unless user

            activity_record(user: user.id, action: 'switch::user', result: 'succeed', topic: 'session')

            Barong::RedisSession.delete(user.uid, session.id)
            session.destroy

            csrf_token = open_session(user)
            publish_session_create(user)

            present user, with: API::V2::Entities::UserWithFullInfo, csrf_token: csrf_token
            status(200)
          end
        end
      end
    end
  end
end
