Q1. What is multi-tenancy?
Multi-tenancy is an architecture where a single application instance serves multiple customers, which we call tenants. Each tenant's data stays logically or physically isolated from the others. The big benefit is that we share infrastructure and code, so it's much more cost-effective than running a separate deployment for every customer.

------------------------------------------------------------------------------------------------------
Q2. What is the difference between single-tenant and multi-tenant?
In single-tenant, every customer gets their own deployment and database. Isolation is complete, but operations and cost are high. In multi-tenant, all customers share the same infrastructure, so updates roll out once for everyone, but we have to be very careful about isolating data in the code and database design.

------------------------------------------------------------------------------------------------------
Q3. What are the different multi-tenancy data models?
There are three main ones. First, shared database and shared schema, where every table has a tenant ID column. It is the cheapest and scales well, but isolation depends on the code. 
Second, shared database with a separate schema per tenant, which gives stronger isolation without the cost of separate databases. 
Third, a separate database per tenant, which gives the strongest isolation but is the most expensive to operate. 

In practice, many systems use a hybrid: small customers in a shared pool, and large enterprise customers on dedicated resources.

------------------------------------------------------------------------------------------------------
Q4. How do you decide which model to use?
I look at four things: how sensitive the data is, whether there are compliance requirements like data residency, how many tenants we expect and how big they get, and how much operational effort the team can handle. For example, for HR or payroll data, I would lean toward stronger isolation. For a high-volume SaaS with thousands of small customers, row-level tenancy is usually more practical.

------------------------------------------------------------------------------------------------------
Q5. How do you identify the tenant in a request?
Usually in a middleware. Common approaches are the subdomain, like acme.app.com, a custom domain for whitelabel setups, a path prefix, or a claim in the JWT for APIs. 
The resolved tenant is stored in a request-scoped context, so the rest of the request uses it without passing it around everywhere.

------------------------------------------------------------------------------------------------------
Q6. How do you prevent data leakage between tenants?
I use defense in depth. At the application level, every query goes through a tenant scope, and I avoid writing raw queries without it. At the database level, I can use Postgres Row-Level Security, so even if the application code forgets the filter, the database itself won't return another tenant's rows. I also write tests that explicitly check that one tenant cannot access another tenant records.

------------------------------------------------------------------------------------------------------
Q7. What is the noisy neighbor problem, and how do you handle it?
It is when one large tenant consumes a disproportionate share of shared resources, like CPU, DB connections, or queue workers, and slows everyone else down. To handle it, I would apply per-tenant rate limits, separate queues for heavy tenants, monitor usage per tenant, and if needed, move that tenant to a dedicated database. That is the pool-to-silo move.

------------------------------------------------------------------------------------------------------
Q8. How do you handle background jobs in a multi-tenant system?

The biggest mistake is assuming the job runs in the right context. I always pass the tenant identifier explicitly as a job argument, and the job sets the tenant context at the start and clears it at the end. This matters a lot with schema-based tenancy, because a job running in the wrong schema could read or write the wrong data.

------------------------------------------------------------------------------------------------------
Q9. How do migrations work in schema-per-tenant?
Every schema has to be migrated. We usually have a rake task or script that loops over all tenant schemas and runs the migration in each one, and it should be idempotent and resumable, so that if it fails halfway, we can rerun it safely. New tenants are provisioned by creating a schema and loading the current schema definition. Migrations can get slow as tenant count grows, so we also monitor failures per tenant.

------------------------------------------------------------------------------------------------------
Q10. What are the pros and cons of schema-per-tenant versus row-level tenancy?
Schema-per-tenant gives better isolation, easier per-tenant backup and restore, and it is easier to explain to compliance teams. But migrations take longer, there is more catalog overhead with thousands of schemas, and cross-tenant queries are harder. Row-level tenancy is simpler to operate and makes cross-tenant analytics easy, but it puts more responsibility on the code and needs careful scoping, or RLS, to stay safe.

------------------------------------------------------------------------------------------------------
Q11. How do you support whitelabel or custom domains?
I map the incoming host to a configuration record, for example a whitelabel config table, which holds the domain, branding, and feature flags. The middleware resolves that host to the organization, and the app renders the right branding. I also make sure the allowed hosts list is updated dynamically, so new custom domains work without a deploy.

------------------------------------------------------------------------------------------------------
Q12. How do you handle caching in a multi-tenant app?
Every cache key includes the tenant ID, for example org:42:accounts. If I forget that, one tenant could see cached data from another tenant. I also consider cache invalidation per tenant, so that changing one tenant's data doesn't flush everyone else cache.

------------------------------------------------------------------------------------------------------
Q13. How do you handle cross-tenant reporting, like an internal admin dashboard?
That is a separate access path. I would create an explicit internal role with an audited, read-only access path, rather than weakening the normal tenant scope. In a row-level design, this is simple. In a schema-per-tenant design, I would either aggregate through a reporting database or iterate over the schemas, which is slower.

------------------------------------------------------------------------------------------------------
Q14. What happens when a tenant grows very large?
That is where the hybrid model helps. I can move that tenant from the shared pool to a dedicated database or cluster. The key is that the tenant resolution layer should be abstracted, so the application knows which database to connect to for a given tenant. That keeps the migration path open from the start.

------------------------------------------------------------------------------------------------------
Q15. How would you onboard a new tenant?
Onboarding is an automated provisioning flow. It creates the tenant record, sets up the subdomain or domain, creates the schema or database if needed, runs migrations, seeds default data like roles and settings, and creates the first admin user. I would make the whole thing idempotent and make sure failures are logged, so it can be retried.