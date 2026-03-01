=================================== AWS ==================================================
Question 1: What is IAM?

Answer: IAM stands for Identity and Access Management. It is AWS’s service to manage who can access AWS and what actions they can perform. IAM lets us define identities like users, groups, and roles, and permission rules using JSON policies.
In real projects, IAM is critical because AWS follows the shared responsibility model, and IAM helps us ensure only authorized people/services can access resources like S3 buckets, EC2, CloudFront distributions, or MediaConvert jobs.

------------------------------------------------------------------------------------------------------
Question 2: IAM user vs role — what is the difference?

Answer: IAM Users are long-term identities, typically used for humans or service accounts. They usually have permanent access keys unless rotated.
IAM Roles are designed for temporary access. Roles are commonly used by AWS services like EC2, Lambda, MediaConvert — they assume the role and get temporary credentials via STS.
In production, roles are preferred because you avoid storing long-lived secrets on servers.
 
------------------------------------------------------------------------------------------------------
Question 3: What is an IAM policy? Explain structure.

Answer: An IAM policy is a JSON document that defines permissions. It contains statements like:
  Effect: Allow/Deny
  Action: e.g., s3:GetObject, s3:PutObject
  Resource: which bucket or object
  Condition: extra restrictions like IP ranges or encryption
Basically, a policy is basically the authorization rules.
 
------------------------------------------------------------------------------------------------------
Question 4: What is least privilege?

Answer: Least privilege means giving minimum required permissions—nothing more.
Example: If my Rails backend only needs to generate presigned URLs for upload to S3, I should allow only:

s3:PutObject on mybucket/uploads/*
Instead of giving s3:* on all buckets.
This limits blast radius and is a security best practice.

------------------------------------------------------------------------------------------------------
Question 5: How should EC2 access S3 securely?

Answer: Best practice is to attach an IAM Role to EC2 (Instance Profile). That role grants required S3 permissions.
This way, the EC2 instance automatically gets temporary credentials and we don’t store AWS keys inside .env or code. This is both secure and easy to rotate.

------------------------------------------------------------------------------------------------------
Question 6: What is EC2(Elastic Compute Cloud)?

Answer: EC2 is AWS’s compute service where you run virtual servers. 
You choose instance type (CPU/RAM - Decides how powerful it should be), 
OS image (AMI - Amazon Machine Image), 
Storage (EBS -  Elastic Block Store - hard disk/SSD storage attached to an EC2 instance), and 
Networking configuration (VPC - Virtual Private Cloud - your private network inside AWS)

For Rails deployment, EC2 is commonly used when teams want full control over server setup like Nginx, Puma, Sidekiq, Postgres, etc.

EBS is persistent block storage. If instance dies, we can reattach EBS to another instance, and snapshots help with backup.

Inside a VPC you define:
  IP address range (CIDR)
  subnets
  routing tables
  gateways
  security rules

  So VPC basically controls:
    which servers are public
    which are private
    who can talk to who

  => VPC gives network isolation. We design public/private subnets and control inbound/outbound traffic for security.

Subnet (Public vs Private) - A subnet is a smaller network inside VPC.
Public subnet:
  has route to Internet Gateway (IGW)
  used for: Load Balancer, Bastion, public-facing EC2

Private subnet
  no direct internet access
  used for: DB (RDS), Redis, internal app servers

Rails best practice:
  Load Balancer in public subnet
  Rails app servers in private subnet
  DB in private subnet

Security Group (SG): Security Group means firewall for your EC2 instance.
  It defines allowed ports:
  allow 80/443 from internet (HTTP/HTTPS)
  allow 22 only from office IP / bastion (SSH)
  allow 5432 only from app servers (Postgres)

=> Security groups are stateful firewalls attached to instances; we open only required ports.

------------------------------------------------------------------------------------------------------
Question 7: How do you host Rails on EC2?

Answer: Typical setup steps includes:
  EC2 instance (Ubuntu)
  Nginx as reverse proxy
  Rails app running with Puma
  Background jobs using Sidekiq (Redis)
  Database using RDS or Postgres installed
  Deployment via Capistrano / CI/CD / Docker

  I also ensure:
    systemd keeps services running
    logs shipped to CloudWatch or stored properly
    security group opens only necessary ports

------------------------------------------------------------------------------------------------------
Question 8: What is a Security Group?

Answer:A security group is like a firewall at the instance level. It controls allowed inbound and outbound network traffic.
Example:
  Allow inbound 22 (SSH) only from my IP
  Allow inbound 80/443 to public
  Allow DB port only from internal services
  Security groups are stateful: if inbound is allowed, response traffic is allowed automatically.

------------------------------------------------------------------------------------------------------
Question 9: What is EBS and why is it important?

Answer: EBS is persistent block storage used by EC2 instances. Even if you stop and start the instance, EBS retains data. It is important for storing app files, logs, and system configurations. Also you can take EBS snapshots for backups.

------------------------------------------------------------------------------------------------------
Question 10: What is S3 multipart upload?

Answer: Multipart upload is used for uploading large files by splitting them into multiple parts. Instead of uploading a file in one request, the client uploads parts separately.
This improves reliability because if one part fails, we only retry that part.
It also improves upload speed as parts can be uploaded in parallel.

------------------------------------------------------------------------------------------------------
Question 11: Explain multipart upload flow (step-by-step)

Answer:Multipart upload has 3 main steps:
  CreateMultipartUpload → returns uploadId
  UploadPart (part 1..n) → returns ETag for each part
  CompleteMultipartUpload → send list of {partNumber, etag} → S3 merges parts
So uploadId is the identity of that file upload session.

------------------------------------------------------------------------------------------------------
Question 12: How does resume support work in multipart upload?

Answer: Resume support means if upload stops at 60 - 70% then we do not restart.
We store:
  uploadId 
  uploaded part numbers
  file info

When resuming:
  call ListParts using uploadId
  identify which parts already exist
  continue uploading remaining parts only
  This is very useful for unstable networks.

------------------------------------------------------------------------------------------------------
Question 13: What is ETag in multipart upload?

Answer: ETag is a hash identifier returned for each uploaded part.
When completing multipart upload, we must provide each part’s number and ETag. S3 uses these to verify the final object is assembled correctly.
If ETags do not match, completion fails.

------------------------------------------------------------------------------------------------------
Question 14: What happens if multipart upload never completes?

Answer:S3 keeps the incomplete parts stored, which can waste storage and cost.
So best practice is to configure an S3 lifecycle rule:
  AbortIncompleteMultipartUpload after X days

------------------------------------------------------------------------------------------------------
Question 15: Presigned URL — what and why?

Answer: Presigned URL is a signed URL generated by backend that allows client to upload/download directly to S3 without exposing AWS credentials.
In Rails systems, this is best because:
  Rails server does not handle file bytes (no load)
  upload is faster
  scaling becomes easy

------------------------------------------------------------------------------------------------------
Question 16: How do you restrict file types and size?

Answer: We enforce it at multiple levels:
  backend validation (extension, mime-type)
  use presigned POST policy conditions (size range, content-type)
  S3 bucket policy conditions can enforce encryption

  This avoids users uploading random or huge files.

------------------------------------------------------------------------------------------------------
Question 17: What is CloudFront and why use it?

Answer: CloudFront is AWS CDN. It caches and serves content from edge locations near the user.
Benefits:
  low latency
  higher download speed
  reduced origin traffic (S3/EC2)
  supports HTTPS, signed URLs, WAF
  In streaming, CloudFront is critical for smooth playback.

------------------------------------------------------------------------------------------------------
Question 18: CloudFront vs S3 direct

Answer: S3 is storage. It serves objects but does not optimize distribution.
CloudFront provides caching at edge, advanced access control, and better user performance.
For video streaming, you generally serve HLS segments through CloudFront instead of direct S3 URLs.

------------------------------------------------------------------------------------------------------
Question 19: How do you secure video content on CloudFront?

Answer: We typically:
keep S3 private (Block Public Access)
allow S3 access only from CloudFront (OAC/OAI)
use CloudFront signed URLs / signed cookies for viewer access
This prevents users from bypassing CloudFront and accessing S3 directly.

------------------------------------------------------------------------------------------------------
Question 20: Signed URLs vs Signed cookies?

Answer: Signed URL is best when granting access to one file.
Signed cookies are better when granting access to multiple files, like an entire HLS(HTTP Live Streaming) directory containing playlist + segments.
In streaming projects, signed cookies are commonly used.

------------------------------------------------------------------------------------------------------
Question 21: Why playlists (.m3u8) need different caching strategy?

Answer: Because playlist content updates frequently (especially live).
If CloudFront caches playlist too long, user may see old segment list or delay.
So we set:
  low TTL(Time To Live) for .m3u8
  higher TTL for .ts/.m4s segments
  This improves both freshness and performance.

Detailed Answer:
1. What is a playlist (.m3u8) in streaming?
  In HLS (HTTP Live Streaming): .m3u8 file is a playlist / index 
    It does NOT contain video
    It contains a list of video segment URLs in order

  Example (conceptually):
    #EXTM3U
    segment_101.ts
    segment_102.ts
    segment_103.ts

So the player first downloads .m3u8, then downloads those .ts or .m4s segments.

2. Why does playlist caching need to be different?
Because playlist changes frequently.
Case A: Live streaming
    Every few seconds: 
      a new segment is produced (e.g., segment_200.ts)
      playlist is updated to include that new segment
    So playlist might update like:
      At 10:00:00
        segment_10.ts
        segment_11.ts
        segment_12.ts

      At 10:00:06
        segment_11.ts
        segment_12.ts
        segment_13.ts

    So playlist is “moving forward”.
    Meaning: playlist is dynamic and must stay fresh.

3. What happens if CloudFront caches playlist too long?
  If CloudFront caches .m3u8 for long time (say 60s):
    user keeps receiving old playlist
    player does not see the new segments
    playback becomes delayed / stuck / buffering
    live stream becomes “behind real time”

  Example:
    Your origin has segment_13.ts ready
    but CDN still gives playlist showing only till segment_12.ts
    player keeps requesting same old list

  So you get:
    latency
    stale playback
    sometimes looping segments
    “live is not live” issue

4. Why segments (.ts / .m4s) can have higher caching?
   Because segments are usually immutable.

  Meaning:
    segment_120.ts once generated will never change
    it is a fixed file
    So caching segments for long time is safe.

  Benefits:
    huge performance gain
    much lower origin load
    faster playback
    lower cost (less origin bandwidth)

  So strategy is:
  .m3u8 playlist:
    low cache
    because frequently updated

  .ts / .m4s segments:
    high cache
    because never changes

Playlists are dynamic and represent the latest available segments, so we keep TTL low to avoid stale playback. Segments are immutable, so we cache them aggressively with high TTL to improve cost and performance.

5. Master playlist vs media playlist.
    In HLS there are two types of .m3u8:

  A. Master playlist: points to different qualities (240p/480p/720p).
      usually static
      TTL can be higher

  B. Media playlist:
      the real segment list
      changes frequently for live
      TTL must be low
      This is a strong interview bonus point.

------------------------------------------------------------------------------------------------------
Question 23: What is AWS Elemental MediaConvert?

Answer: MediaConvert is AWS managed file-based transcoding service. It converts uploaded videos into different formats like: MP4, HLS (adaptive streaming), DASH etc. It is commonly used in OTT/video platforms for generating multiple renditions.

------------------------------------------------------------------------------------------------------
Question 24: Why MediaConvert? Why not Elastic Transcoder?

Answer: Elastic Transcoder was the older service and AWS has retired it (Nov 2025).
MediaConvert is the replacement and provides more features like:
  advanced encoding controls
  ABR(Adaptive Bitrate streaming) ladder configs
  better scalability and integration

------------------------------------------------------------------------------------------------------
Question 25: What is a MediaConvert job?

Answer: A job defines:
  input source (S3)
  codec settings
  output settings (HLS/MP4)
  output destination (S3)
  Once job completes, the output files are available in destination bucket.

------------------------------------------------------------------------------------------------------
Question 26: ABR Streaming using MediaConvert

Answer: ABR means multiple renditions, like:
  1080p high bitrate
  720p medium
  480p low
MediaConvert generates these and creates a master playlist for HLS. Player automatically switches quality based on network.
 
------------------------------------------------------------------------------------------------------
Question 27: How do you trigger MediaConvert after upload?

Answer: Most common approach:
  S3 upload completes
  S3 event triggers backend/Lambda
  backend calls MediaConvert CreateJob API
  Then output files go to another S3 bucket and served through CloudFront.


===================================== S3 Multipart Upload =========================================== 
Question 28: What is the minimum part size in multipart upload and why?

Answer: In S3 multipart upload, the minimum part size is five MB for each part, except the last part, which can be smaller. The reason is efficiency — each part has metadata and storage overhead, so if parts are too small, we end up with too many parts, which increases overhead and slows the system. That is why AWS enforces a minimum size to keep uploads scalable and manageable.

------------------------------------------------------------------------------------------------------
Question 29: What is the maximum number of parts?

Answer: S3 allows a maximum of ten thousand parts in a single multipart upload. So when we choose part size, we make sure the total number of parts does not exceed this limit. For very large files, we increase the part size so file size divided by part size stays within ten thousand.
 
------------------------------------------------------------------------------------------------------
Question 30: How do you handle concurrency when uploading parts?

Answer: One big advantage of multipart upload is that parts can be uploaded in parallel. Typically, the client splits the file into chunks and uploads multiple parts concurrently, like four or eight parallel uploads. This improves upload speed significantly. In implementation, we upload parts in parallel, collect the ETag for each part, and once all parts are uploaded successfully, we call CompleteMultipartUpload. We also keep concurrency balanced because too much parallelism can overload the network or cause failures.

------------------------------------------------------------------------------------------------------
Question 31: What if client uploads parts out of order?

Answer: That is totally supported. Multipart upload doesn’t require parts to be uploaded in order. S3 identifies each part by the part number, so part seven can be uploaded before part two without any issue. When completing the upload, we send the list of uploaded parts along with their part numbers and ETags, usually sorted, and S3 assembles the final file correctly.
 
------------------------------------------------------------------------------------------------------
Question 32: How do you securely store uploadId for resume support?

Answer: The uploadId is basically the identifier for the multipart upload session. For resume support, we need to store it safely along with file key and user information. The common approach is to store uploadId in the database mapped to the user and the file record. If we store anything client-side like localStorage, we still validate it through the backend. Also, we ensure authorization — only the same user who initiated the upload should be allowed to resume it.

------------------------------------------------------------------------------------------------------
Question 33: How do you clean abandoned uploads?

Answer: If a multipart upload is started but never completed, S3 keeps those parts, which can create unnecessary cost. The best way to handle this is by adding an S3 lifecycle rule to automatically abort incomplete multipart uploads after a few days. Another option is manually listing multipart uploads and calling AbortMultipartUpload. But in production, lifecycle rules are the cleanest and most reliable approach.

------------------------------------------------------------------------------------------------------
Question 34: What happens if the same part number is uploaded again?

Answer: If the same part number is uploaded again, S3 simply replaces the previous part with the new one. Only the latest uploaded version of that part number will be used when completing the multipart upload. This is very useful for retries — if a part fails or becomes corrupted, we can re-upload the same part number and continue

------------------------------------------------------------------------------------------------------
Question 35: How do you verify integrity of the uploaded file?

Answer: At the part level, S3 returns an ETag for each uploaded part, and during CompleteMultipartUpload we provide part number and ETag, which ensures the final object is assembled correctly. At the full file level, we can validate integrity by comparing the final uploaded object size with the expected file size. In more advanced setups, we can compute checksums like SHA-256 and verify them, but practically size check plus successful complete operation works well.

------------------------------------------------------------------------------------------------------
Question 36: Difference between presigned URL upload vs multipart upload?

Answer: A presigned URL upload is usually a single PUT request and is best for smaller or medium size files. Multipart upload is designed for large files and is much more reliable because it supports resume, retry per part, and parallel uploads. In real projects, for small files presigned PUT is enough, but for large media uploads, multipart upload is the better choice.

------------------------------------------------------------------------------------------------------
Question 37: How do you handle very slow networks or mobile uploads?

Answer: For slow or unstable networks, multipart upload is ideal because it supports retries and resume. We reduce concurrency to avoid overwhelming the network, we retry failed parts with exponential backoff, and we persist state — like uploadId and completed part numbers — so the user can resume without restarting from zero. We also implement progress tracking and optional pause-resume support to improve the user experience.

===================================== CloudFront Streaming =========================================== 
CloudFront is a CDN that caches content at global edge locations and delivers it to users with low latency and high transfer speed.

Question 38: How do you prevent S3 bypass?

Answer: To prevent S3 bypass, the main rule is: S3 bucket should not be public. We enable Block Public Access and restrict access so only CloudFront can read objects from the bucket. We do that using OAC or the older OAI mechanism. That way, users cannot access the S3 object directly even if they know the URL, and they must go through CloudFront where we can enforce rules like signed URLs or signed cookies.

------------------------------------------------------------------------------------------------------
Question 39: OAI vs OAC — which one and why?

Answer: OAI is the older CloudFront mechanism to access private S3 content. OAC is the newer recommended approach and it uses SigV4 signing. OAC is considered more secure and flexible, and AWS recommends OAC for new implementations. So if I’m building it today, I would choose OAC.

------------------------------------------------------------------------------------------------------
Question 40: Signed URL vs signed cookies — which for HLS and why?

Answer: For HLS streaming, signed cookies are usually a better option. The reason is HLS involves multiple files — playlists and a lot of segment files. If we use signed URLs, we would have to sign every segment URL, which becomes messy and inefficient. Signed cookies allow access to an entire path like /hls/video123/*, so the player can fetch playlist and segments smoothly while still keeping the content private.”

------------------------------------------------------------------------------------------------------
Question 41: What caching settings for playlists and segments?

Answer: In HLS, playlist files .m3u8 change frequently, so we keep their TTL low, especially for live streaming — maybe a few seconds. Segment files like .ts or .m4s are mostly immutable, so we set higher TTL — like an hour or more. This avoids stale playlists while maximizing caching for segments, which improves performance.

------------------------------------------------------------------------------------------------------
Question 42: What is Origin Shield?

Answer: Origin Shield is an extra caching layer in CloudFront. Normally, edge locations hit the origin when cache misses happen. With Origin Shield, CloudFront routes those misses through a designated regional cache layer. This reduces load on the origin and improves cache hit ratio, especially for high traffic systems.”

------------------------------------------------------------------------------------------------------
Question 43: What happens if playlist cached too long?

Answer: If playlist caching TTL is too high, users may receive outdated playlist content. For live streams, it can cause delays, buffering, or even playback freezing because the player does not get the latest segments. That is why we set playlist TTL low and sometimes disable caching for playlist depending on the live use case.”

------------------------------------------------------------------------------------------------------
Question 44: How do you restrict content by geography?

Answer: CloudFront supports geo restriction where we can whitelist allowed countries or blacklist blocked countries. This is configured directly on the distribution settings. It’s commonly used for licensing restrictions.”

------------------------------------------------------------------------------------------------------
Question 45: What is CloudFront invalidation and why costly?

Answer: CloudFront invalidation is used to remove cached objects from edge locations so CloudFront fetches fresh content from origin. It can become costly and slow if used heavily because invalidations have limits and can be chargeable beyond free tier. A better approach is using versioned object names, like hashed filenames, so new deployments naturally use new asset URLs.”

------------------------------------------------------------------------------------------------------
Question 46: Cache policy vs origin request policy?

Answer: A cache policy controls how CloudFront caches content — it defines TTL and what goes into the cache key, like query strings, headers, and cookies. An origin request policy defines what CloudFront forwards to the origin. So basically, cache policy affects caching behavior at edge, and origin request policy affects how requests are sent to S3 or the origin server.”

------------------------------------------------------------------------------------------------------
Question 47: How do you debug CloudFront 403 and 504 errors?

Answer: For 403 errors, I first suspect access permission issues, like CloudFront not being allowed to access S3 due to incorrect bucket policy, OAC setup, or Block Public Access misconfiguration. It can also happen if signed URL or cookies are invalid or expired. So I check CloudFront logs, verify bucket policy, and test unsigned access.
For 504 errors, it usually means origin timeout — either origin is slow, unreachable, or overloaded. So I check origin health, security group rules, server load, and CloudFront origin timeout settings. Improving caching or using Origin Shield also helps.

  403 errors usually mean:
    S3 bucket policy not allowing CloudFront
    missing OAC/OAI permissions
    signed URL/cookie expired or wrong
    WAF blocking
    incorrect viewer protocol policy

  To debug 403 error:
    check CloudFront logs
    check S3 access logs (if enabled)
    verify bucket policy
    test unsigned vs signed

  504 errors usually mean:

    origin timeout (slow EC2 or S3)
    origin not reachable (network/security group)
    high load on origin

  To debug 504 error:
    increase origin timeout settings
    check EC2 CPU/memory
    verify network and security rules
    use Origin Shield + better caching

===================================== IAM Security =========================================== 
Question 48: Bucket policy vs IAM identity policy?

Answer: IAM identity policies are attached to users, roles, or groups and define what that identity can do. Bucket policies are attached directly to the S3 bucket itself and define who can access the bucket and objects. Bucket policies are especially useful for granting access to services like CloudFront or allowing cross-account access.

------------------------------------------------------------------------------------------------------
Question 49: How did you restrict S3 uploads to only one folder?

Answer: To restrict S3 uploads, I scope permissions at the resource level. For example, I allow s3:PutObject only to a specific prefix like mybucket/uploads/user123/*. This ensures the user or service cannot upload files outside the allowed folder. It’s a clean least-privilege design.”

------------------------------------------------------------------------------------------------------
Question 50: How do you grant CloudFront access to S3?

Answer: We keep the S3 bucket private and grant access only to CloudFront. For that, we configure CloudFront OAC or OAI and then update the bucket policy to allow s3:GetObject only for requests coming from that CloudFront distribution. This prevents public access and ensures content can be accessed only through CloudFront.”
 
------------------------------------------------------------------------------------------------------
Question 51: What is explicit deny?

Answer: Explicit deny means if any IAM policy statement denies a specific action, it overrides all allow permissions. Even if one policy allows it, explicit deny will block the request. In AWS permission evaluation, deny always wins.”

------------------------------------------------------------------------------------------------------
Question 52: What is IAM policy evaluation logic?

Answer: AWS policy evaluation works like this: default is always deny. Then AWS checks if there is an explicit deny — if yes, request is denied. If there’s no deny, AWS checks for allow policies. If allow exists and conditions match, then request is allowed. Otherwise it remains denied.”

------------------------------------------------------------------------------------------------------
Question 53: What is a role trust policy?

Answer: A trust policy defines who can assume a role. For example, to allow EC2 to assume a role, we set the trusted entity as the EC2 service. Similarly, we can allow MediaConvert or Lambda to assume roles. Trust policy is about role assumption, not about permissions.”
------------------------------------------------------------------------------------------------------
Question 54: Permission policy vs trust policy?

Answer: Trust policy defines who can assume the role. Permission policy defines what the role can do after it is assumed. Both are required — if a service can assume a role but the role does not have permission to access resources, it still won’t work.”

------------------------------------------------------------------------------------------------------
Question 55: IAM best practices for production?

Answer: In production, best practices are: follow least privilege, use roles instead of access keys, enforce MFA for human users, rotate access keys if any exist, enable CloudTrail for auditing, and optionally use permission boundaries for stricter control. The main goal is to reduce risk and improve traceability.”

------------------------------------------------------------------------------------------------------
Question 56: How do you rotate keys / avoid long-lived keys?

Answer: The best approach is to avoid long-lived keys completely by using IAM roles on EC2, Lambda, and other services. If access keys are required for some reason, we store them in a secrets manager, rotate them periodically, and disable any unused keys.”

------------------------------------------------------------------------------------------------------
Question 57: How do you prevent accidental public access to S3?

Answer: I prevent accidental public S3 access by enabling Block Public Access at bucket level, restricting bucket policies, and avoiding public ACLs. In stricter setups, we can add deny rules that prevent public ACLs entirely. We can also use AWS Config rules or security monitoring to detect and alert if any bucket becomes public.”

===================================== MediaConvert =========================================== 
Question 58: What is a job template and why do you use it?

Answer: In MediaConvert, a job template is a reusable configuration for transcoding jobs. Instead of writing the full job JSON every time, we define a template once with settings like output type, codec configuration, resolutions, bitrate ladder, audio settings, and output destination paths. Then whenever a new video comes in, we simply trigger MediaConvert using the same template and provide the input file location. This makes the pipeline consistent, reduces mistakes, and saves time because we do not manually build job configurations for every upload.

------------------------------------------------------------------------------------------------------
Question 59: How do you generate an ABR ladder in MediaConvert?

Answer: ABR ladder means Adaptive Bitrate renditions. The idea is we generate multiple quality versions of the same video, like 1080p high bitrate, 720p medium, and 480p low. In MediaConvert, we configure this inside the HLS output group by defining multiple outputs with different resolution and bitrate settings. MediaConvert generates all renditions and produces the master playlist. During playback, the video player automatically switches to the best rendition depending on user bandwidth and network conditions.

------------------------------------------------------------------------------------------------------
Question 60: What output group do you use for streaming?

Answer: For streaming, I use the HLS output group in MediaConvert. HLS output group produces everything needed for HTTP Live Streaming — it creates a master playlist, variant playlists, and the actual segment files, like .ts or .m4s. All of these outputs are stored in an S3 bucket, and then CloudFront serves them globally through edge locations to provide smooth streaming performance.

------------------------------------------------------------------------------------------------------
Question 61: H.264 vs H.265 — how do you choose?

Answer: H.264 is the safest default codec because it has the widest device compatibility — it works on almost all browsers, mobile devices, and smart TVs. H.265 gives better compression, meaning smaller files and lower bandwidth usage, but the downside is compatibility is not universal and encoding can be more expensive. So in general web streaming use cases, I prefer H.264 unless the project specifically needs bandwidth optimization and target devices fully support H.265.

------------------------------------------------------------------------------------------------------
Question 62: How do you reduce cost in MediaConvert?

Answer: To reduce MediaConvert cost, I focus on generating only what is needed. For example, I do not create unnecessary high-resolution outputs if users do not need them. I also keep the ABR ladder minimal and practical — like 1080p, 720p, 480p — instead of creating too many renditions. Another cost-saving approach is using S3 lifecycle policies to clean up old outputs. And in enterprise setups, if volume is stable and high, reserved pricing can reduce cost compared to pure on-demand usage.

------------------------------------------------------------------------------------------------------
Question 63: How do you monitor MediaConvert job failure?

Answer: I monitor job failures using multiple layers. First, MediaConvert provides job status directly through the console and APIs, so we can check whether the job is in progress, completed, or failed. Second, we can use EventBridge events for job completion or failure and trigger alerts or workflows automatically. In addition, logs and metrics can be integrated into CloudWatch. In the application side, we usually store job IDs in DB and periodically check status, and if failures are transient, we implement retry logic.

------------------------------------------------------------------------------------------------------
Question 64: What service triggers MediaConvert jobs in your architecture?

Answer: A common architecture is: once the video is uploaded to S3, we trigger transcoding. This can be done using S3 event notifications. That event can trigger a Lambda function or hit an API endpoint in the backend. Then the Lambda or backend calls MediaConvert CreateJob API using a job template. This creates an automated pipeline where uploads are automatically converted into streaming-ready outputs.
------------------------------------------------------------------------------------------------------
Question 65: How do you handle thumbnails using MediaConvert?

Answer: For thumbnails, MediaConvert supports frame capture. We configure frame capture settings to extract images at specific intervals or at a specific timestamp, like one image every few seconds. These thumbnails are stored in S3, usually in a separate thumbnail path. Then we can serve them via CloudFront just like any other static asset, for example for previews or video listing pages.

------------------------------------------------------------------------------------------------------
Question 66: What is DRM support conceptually? Have you used it?

Answer: DRM stands for Digital Rights Management. It is used to protect video content so only authorized users can play it. Typically, the content is encrypted and the player requests a license key from a DRM license server. MediaConvert supports integration for DRM workflows in packaging formats like HLS or DASH. Personally, I understand DRM conceptually, but I have not implemented a full DRM end-to-end system in production.

------------------------------------------------------------------------------------------------------
Question 67: Where do MediaConvert logs go?

Answer: MediaConvert provides job-level status and event details, and job completion or failure events can be sent to EventBridge. For centralized monitoring, we integrate events and metrics into CloudWatch. The actual output artifacts — playlists, segments, thumbnails — are stored in S3. So in a typical setup: operational events go through EventBridge and monitoring goes through CloudWatch, while content output goes to S3 and is delivered via CloudFront.

===================================== EC2 & Deployment =========================================== 
Question 68: How do you manage secrets in EC2?

Answer: In EC2, I never hardcode secrets in code or commit them to Git. In production, I inject secrets at runtime using environment variables or a secrets manager. For example, I can store database passwords and API keys in AWS Systems Manager Parameter Store or AWS Secrets Manager and load them during deployment. For Rails specifically, I keep RAILS_MASTER_KEY outside the repo and set it securely on the server so Rails can decrypt credentials. Also, for AWS access from EC2, I prefer IAM Roles instead of long-lived access keys.

------------------------------------------------------------------------------------------------------
Question 69: How do you do zero-downtime deploy on EC2?

Answer: To achieve zero downtime on EC2, I run Rails behind Nginx and Puma. During deployment, I deploy the new release into a separate directory and then switch the symlink to point to the new release, which is the standard Capistrano approach. I restart Puma gracefully, like phased restart, so existing requests complete without being killed. Database migrations are the risky part, so I follow backward-compatible migrations—like adding columns first and removing later in a separate release. For Sidekiq, I restart workers in a controlled way so jobs are not lost and workers pick up the latest code.

------------------------------------------------------------------------------------------------------
Question 70: How do you monitor memory/CPU?

Answer: I monitor EC2 using CloudWatch metrics like CPU utilization, network usage, disk I/O, and if needed memory metrics using the CloudWatch agent. I configure CloudWatch alarms so we get notified when CPU, memory, or disk crosses a threshold. On the server side, I also check system tools like top, htop, and free -m to troubleshoot. From the application side, I monitor logs and request performance to identify slow queries or memory leaks.

------------------------------------------------------------------------------------------------------
Question 71: How do you scale EC2?

Answer: There are two main ways to scale EC2. First is vertical scaling, where we increase instance size for more CPU or RAM. Second is horizontal scaling, where we add more EC2 instances behind a load balancer like ALB. In production, horizontal scaling is preferred because it improves availability. We can also use Auto Scaling Groups to automatically add or remove instances based on traffic or CPU. For Rails, the key is making the app stateless so multiple instances can run in parallel smoothly.

------------------------------------------------------------------------------------------------------
Question 72: ALB vs Nginx?

Answer: ALB and Nginx solve different problems. ALB is a managed load balancer provided by AWS. It distributes incoming traffic to multiple targets, supports health checks, and can handle SSL termination. Nginx runs inside the server and works as a reverse proxy in front of Puma. It’s great for serving static assets, doing request buffering, and forwarding requests efficiently. In many real production setups, ALB is used at the edge, and Nginx runs inside each EC2 instance.

------------------------------------------------------------------------------------------------------
Question 73: How do you handle SSL?

Answer: In AWS setups, the most common approach is to terminate SSL at ALB using ACM certificates. That way SSL is managed by AWS and renewal is automatic. Another approach is to terminate SSL at CloudFront when using CDN. Terminating SSL directly on Nginx with Certbot is possible but it adds operational overhead like renewal management, so it is less preferred in production compared to ACM.

------------------------------------------------------------------------------------------------------
Question 74: Redis/Postgres on EC2 vs managed services?

Answer: Running Postgres and Redis on EC2 gives full control, but it also means we are responsible for backups, monitoring, replication, failover, and patching. For production reliability, managed services are usually better. For Postgres, we use RDS, which provides automated backups, failover, and maintenance. For Redis, we use ElastiCache, which gives stable performance and high availability. EC2-based databases are okay for smaller apps or cost-saving initially, but managed services are more production-ready.

------------------------------------------------------------------------------------------------------
Question 75: How do you ensure EC2 security?

Answer: I secure EC2 using multiple layers. First, I restrict security groups to allow only necessary ports—like 80/443 for HTTP and port 22 for SSH only from trusted IPs. I avoid using password login and use SSH keys. I also keep OS packages updated and disable unnecessary services. For AWS permissions, I attach IAM roles to EC2 instead of storing AWS keys. Finally, I enable monitoring and logging using CloudWatch so abnormal activity is detected early.

------------------------------------------------------------------------------------------------------
Question 76: What is VPC and subnet basics?

Answer: A VPC is a private network created inside AWS where we launch resources. Inside a VPC, we create subnets, which are smaller network segments. Public subnets usually have route to the internet gateway, so services like web servers can receive traffic. Private subnets do not allow direct internet access, so they are used for internal services like databases. A typical architecture is to keep web EC2 instances in public subnet and databases in private subnet for better security.

------------------------------------------------------------------------------------------------------
Question 77: How do you restrict SSH?

Answer: To restrict SSH, I allow port 22 only from fixed trusted IPs like office IP or VPN IP. I disable password authentication and allow only key-based login. For more secure setups, I use a bastion host or AWS SSM Session Manager so SSH access is not exposed publicly. This reduces the attack surface significantly.


