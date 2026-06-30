/*
===============================================================================================
                       AWS for NODE.JS BACKEND DEVELOPERS
===============================================================================================
(Mirrors my aws_question.rb. Most AWS knowledge — IAM, EC2, S3, VPC, security groups — is
cloud-fundamentals, identical regardless of language. This file keeps that core and adds the
Node-specific bits: aws-sdk v3, presigned URLs, and the Node deployment options EC2 vs ECS vs Lambda.)
*/

/*
-----------------------------------------------------------------------------------------------
Q1: IAM — users, roles, policies, least privilege (cloud fundamentals, unchanged)
-----------------------------------------------------------------------------------------------
Answer ->
  IAM (Identity & Access Management) controls WHO can access AWS and WHAT they can do.
   - IAM USER: long-term identity (a human / service account), usually with permanent access keys.
   - IAM ROLE: temporary credentials assumed by a service (EC2, Lambda, ECS) via STS. PREFERRED in
     production because you don't store long-lived secrets on servers.
   - IAM POLICY: a JSON doc of permissions — Effect (Allow/Deny), Action (s3:GetObject), Resource
     (which bucket), optional Condition (IP, encryption).
   - LEAST PRIVILEGE: grant the minimum needed. If my Node backend only generates presigned upload
     URLs, allow just `s3:PutObject` on `mybucket/uploads/*`, not `s3:*`. Limits blast radius.

  Node-specific best practice: DON'T put AWS keys in .env on an EC2 box. Attach an IAM ROLE
  (instance profile) to the instance; the aws-sdk picks up temporary credentials automatically via
  the default credential chain. Same for ECS task roles and Lambda execution roles.
*/

/*
-----------------------------------------------------------------------------------------------
Q2: S3 from Node (aws-sdk v3) — the most common AWS task for a backend dev
-----------------------------------------------------------------------------------------------
Answer -> S3 is object storage (files, images, backups, the EDI files from my Horizon project).
aws-sdk v3 is modular (import only the client you need).

  const { S3Client, GetObjectCommand, PutObjectCommand } = require('@aws-sdk/client-s3');
  const s3 = new S3Client({ region: process.env.AWS_REGION });
  // no keys passed -> the SDK uses the IAM role / env / shared config (default credential chain)

  // upload
  await s3.send(new PutObjectCommand({ Bucket, Key: 'uploads/a.jpg', Body: buffer, ContentType: 'image/jpeg' }));

  // download / stream (the byte-range trick I used for the EDI import — file 27)
  const res = await s3.send(new GetObjectCommand({ Bucket, Key, Range: 'bytes=0-1048575' }));
  // res.Body is a Node Readable stream -> pipe it, don't buffer huge files in memory.
*/

/*
-----------------------------------------------------------------------------------------------
Q3: Presigned URLs (the right way to handle large client uploads/downloads)
-----------------------------------------------------------------------------------------------
Answer -> Instead of proxying a big file THROUGH my Node server (which buffers/streams it and uses
my bandwidth + event loop), I generate a short-lived PRESIGNED URL and let the client talk to S3
DIRECTLY. The server only signs; the bytes never transit Node.

  const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
  const url = await getSignedUrl(s3,
    new PutObjectCommand({ Bucket, Key: `uploads/${userId}/${filename}` }),
    { expiresIn: 300 });   // valid 5 minutes
  // return `url` to the client; it PUTs the file straight to S3.

  This is the scalable upload pattern (also in file 28), and it pairs perfectly with least-privilege
  IAM: the backend only needs s3:PutObject on the uploads prefix.
*/

/*
-----------------------------------------------------------------------------------------------
Q4: EC2, VPC, subnets, security groups (cloud networking — language-agnostic)
-----------------------------------------------------------------------------------------------
Answer ->
  EC2: virtual servers. You choose instance type (CPU/RAM), AMI (OS image), EBS (persistent disk),
       and networking. Used when you want full control of the box.
  EBS: persistent block storage; survives stop/start; snapshot for backups.
  VPC: your private network in AWS — defines IP ranges (CIDR), subnets, routing, gateways. Gives
       network isolation.
  SUBNETS:
    - PUBLIC subnet (route to Internet Gateway): load balancer, bastion, public-facing servers.
    - PRIVATE subnet (no direct internet): app servers, DB (RDS), Redis.
    Best practice: load balancer in public subnet; Node app servers + DB in private subnets.
  SECURITY GROUP: a stateful instance-level firewall. Open only required ports:
    - 80/443 from the internet, 22 (SSH) only from your IP/bastion, 5432 (Postgres) only from app SG.

  For a Node deploy on EC2: Nginx as reverse proxy -> Node app (PM2 in cluster mode) -> RDS Postgres
  + ElastiCache Redis (for BullMQ/cache). systemd/PM2 keeps it running; ship logs to CloudWatch;
  SG opens only necessary ports. (Same shape as my Rails Nginx+Puma+Sidekiq+RDS setup, Node tools.)
*/

/*
-----------------------------------------------------------------------------------------------
Q5: How do you deploy a Node app on AWS? (EC2 vs ECS/Fargate vs Lambda — know the trade-offs)
-----------------------------------------------------------------------------------------------
Answer -> Three common targets:
  - EC2 (+ PM2): full control, you manage the OS, patching, scaling. Good when you need that control.
    Run Node behind Nginx, PM2 in cluster mode for all cores, autoscaling group for horizontal scale.
  - ECS / Fargate (containers): package the app as a Docker image (file 31), push to ECR, run as a
    service with N tasks behind an ALB. Fargate = no servers to manage. My DEFAULT for most Node
    services — clean scaling, rolling deploys, health checks; k8s/EKS is the heavier alternative.
  - Lambda (serverless): event-driven functions, pay-per-use, auto-scales to zero. Great for spiky/
    event workloads (S3 triggers, API Gateway endpoints, cron). Watch-outs for Node: cold starts,
    15-min max, and DB connection limits (use RDS Proxy / keep connections out of the handler).

  "For a steady API I'd containerize and run on ECS Fargate behind an ALB; for spiky event-driven
   work I'd use Lambda; EC2+PM2 when I need full control of the host."
*/

/*
-----------------------------------------------------------------------------------------------
Q6: Other AWS services a Node backend commonly touches
-----------------------------------------------------------------------------------------------
Answer ->
  RDS            -> managed Postgres/MySQL (use RDS Proxy to bound connections — file 28).
  ElastiCache    -> managed Redis (for BullMQ queues, caching, sessions, rate limiting).
  S3             -> object storage + presigned URLs (above).
  CloudFront     -> CDN in front of S3/the app (cache static assets, lower latency).
  SQS / SNS      -> managed message queue / pub-sub (an alternative to self-hosted BullMQ for
                    decoupled, cross-service messaging — file 25).
  Secrets Manager / SSM Parameter Store -> store secrets, inject as env at runtime (file 19).
  CloudWatch     -> logs + metrics + alarms (ship pino logs here).
  ALB            -> load balancer + health checks + TLS termination in front of ECS/EC2.
  ECR            -> private Docker registry for your images.
*/

/*
-----------------------------------------------------------------------------------------------
Q7: Infrastructure as Code (I have Azure + Pulumi exposure — frame it)
-----------------------------------------------------------------------------------------------
Answer -> Don't click in the console for prod — define infra as code so it's versioned, reviewable,
and reproducible. Options: Terraform, AWS CDK, the Serverless Framework, or Pulumi (which lets you
write infra in TypeScript/JS — natural for a Node dev).

  // Pulumi in TypeScript (I've used Pulumi on Azure; same idea on AWS)
  const bucket = new aws.s3.Bucket('uploads');
  const role = new aws.iam.Role('app-role', { assumeRolePolicy: ... });

  "I've used Pulumi with Azure (VNets/subnets/delegation) — equivalent to AWS VPC/subnets. The
   value is the same everywhere: infra in code, peer-reviewed, repeatable across environments."
   (Azure parallels: VNet ≈ VPC, NSG ≈ Security Group, App Service ≈ Elastic Beanstalk/ECS.)
*/

module.exports = {};
