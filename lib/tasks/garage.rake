# Applies the bucket CORS policy that browser direct-uploads require. The composer
# PUTs the image straight to the Garage endpoint cross-origin, so without a bucket
# CORS rule the browser preflight fails ("Response to preflight request doesn't pass
# access control check") even after CSP allows the host. Reuses the same GARAGE_* env
# and aws-sdk-s3 (already bundled) the Active Storage `garage` service uses, so there
# is nothing to install — run it on a box where the GARAGE_* vars are set:
#
#   bin/rails garage:cors
#
# Override the allowed origin(s) with a comma-separated CORS_ORIGINS (default is the
# production host). Idempotent: put_bucket_cors replaces the whole policy each run.
namespace :garage do
  desc "Apply the direct-upload CORS policy to the Garage bucket (CORS_ORIGINS to override)"
  task cors: :environment do
    bucket = ENV.fetch("GARAGE_BUCKET")
    origins = ENV.fetch("CORS_ORIGINS", "https://hoojah.rudzainy.com").split(",").map(&:strip)

    client = Aws::S3::Client.new(
      endpoint: ENV.fetch("GARAGE_ENDPOINT", "https://s3-grg.novas.my"),
      access_key_id: ENV.fetch("GARAGE_ACCESS_KEY_ID"),
      secret_access_key: ENV.fetch("GARAGE_SECRET_ACCESS_KEY"),
      region: ENV.fetch("GARAGE_REGION", "garage"),
      force_path_style: true
    )

    client.put_bucket_cors(
      bucket: bucket,
      cors_configuration: {
        cors_rules: [{
          allowed_origins: origins,
          allowed_methods: ["PUT"], # serving is same-origin via the AS proxy; only the upload PUT is cross-origin
          allowed_headers: ["*"],
          expose_headers: ["ETag"],
          max_age_seconds: 3600
        }]
      }
    )

    applied = client.get_bucket_cors(bucket: bucket).cors_rules.map(&:to_h)
    puts "Applied CORS to bucket #{bucket.inspect} for origins #{origins.inspect}:"
    puts applied.inspect
  end
end
