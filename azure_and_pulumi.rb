1.What is VNet (Virtual network)?
  Answer: VNet is like a private network boundary in Azure where I can isolate my resources. It allows me to define IP ranges, control traffic flow, and ensure secure communication between services like App Service and PostgreSQL without exposing them to the public internet.

  Without VNet, all services communicate over public internet. In production, that is insecure. By using VNet, I ensure my backend talks to database privately over internal IP, which reduces attack surface and improves security posture.

  It is similar to VPC (Vitual private cloud) of AWS.

  VNet simaply means: Your private home in Azure Cloud where your services communicates privately using azure internal backbone private network. When we use VNet then all resources inside VNet gets their own private IP.

---------------------------------------------------------------------------------------------------------
2.What is Subnet?
  Answer: Subnet is logical partition inside VNet.
  Subnet is used to segment the network. We can create separate subnets for difference services. For example we can create seperate subnet for App Service and PostgreSQL to isolate workloads and apply service-specific configurations like delegation.

---------------------------------------------------------------------------------------------------------
3.What is Subnet Delegation?
  Answer: Subnet delegation allows a specific Azure service to fully control that subnet. For example, PostgreSQL Flexible Server requires a delegated subnet so Azure can manage networking internally. Without delegation, the service deployment will fail.

  Example: Pulumi example.
    const dbSubnet = new network.Subnet("my-db-subnet", {
      resourceGroupName: rg,
      virtualNetworkName: vnet.name,
      addressPrefix: "10.0.2.0/24",

      delegations: [{
        name: "postgresDelegation",
        serviceName: "Microsoft.DBforPostgreSQL/flexibleServers",
      }],
    });

  Subnet delegation in Azure means assigning a subnet to a specific Azure service, so that the service can deploy and manage resources within that subnet.

  When a subnet is delegated:
    Only the specified Azure service can use that subnet
    Azure automatically configures the required network settings
    It ensures proper integration between the service and the Virtual Network
    
  Normally, we control what gets deployed in a subnet. But with delegation, we give that control to an Azure service like App Service or Azure Database.
  This allows the service to manage IP allocation, routing, and other configurations automatically

 🔸What is addressPrefix: "10.0.2.0/24"?
   It means This subnet will contain IP addresses from the range 10.0.2.0 to 10.0.2.255

   ➤Breaking it down:
    10.0.2.0 => This is the network address.It identifies the subnet.

    /24 => This is CIDR (Classless Inter-Domain Routing) notation. /24 means "24 bits are fixed for network, remaining 8 bits are for hosts"
    So:
      Total IPs = 2^8 = 256 IP addresses
      Usable IPs ≈ 251-253 (Azure reserves some)


  NOTE:
    addressPrefix defines the IP range of a subnet using CIDR notation, and in this case 10.0.2.0/24 means the subnet contains 256 IP addresses from 10.0.2.0 to 10.0.2.255.
    A subnet address prefix determines the size and IP range of a subnet, and it is crucial for network segmentation and IP allocation in Azure VNets.


------------------------------------------------------------------------------------------------------------------
4.What is CIDR (Classless Inter-Domain Routing)?
  Answer: CIDR is a way to define how big a network/subnet is using a suffix like /16, /24, /28.
  It tells: “How many IP addresses are available in this subnet?”

  CIDR notation defines the size of a network by specifying how many bits are reserved for the network portion. A smaller CIDR number means a larger number of IP addresses.

 🔸Basic rule
    IPv4 address has 32 bits total.
    CIDR tells:
      how many bits are used for network
      remaining bits are for hosts (devices/IPs)

 🔸Common CIDR sizes
   🔹/16 → Large network
           Host bits = 32 - 16 = 16
           IPs = 2¹⁶ = 65,536 IPs

          Example range:
            10.0.0.0/16
            Covers: 10.0.0.0 → 10.0.255.255

        Used for: large systems, big VNets

   🔹/24 → Medium network (most common)
           Host bits = 8
           IPs = 2⁸ = 256 IPs

          Example:
            10.0.2.0/24
            Covers: 10.0.2.0 → 10.0.2.255

        Used for: app subnets, DB subnets

   🔹/28 → Small network
           Host bits = 4
           IPs = 2⁴ = 16 IPs

          Example:
            10.0.2.0/28
            Covers: 10.0.2.0 → 10.0.2.15
        
        Used for: small services, limited resources

    NOTE:
      /16 = very large network, /24 = medium subnet, /28 = small subnet with limited IPs./

--------------------------------------------------------------------------------------------------------------------
5.What is WEBSITE_VNET_ROUTE_ALL = 1 ?
  Answer: This forces all outbound traffic from App Service to go through VNet. For example It ensures that database calls go through private network instead of public internet.
  WEBSITE_VNET_ROUTE_ALL only affects new outbound connections from App Service. Responses to incoming client requests are part of the same connection and are not routed through VNet.

-----------------------------------------------------------------------------------------------------------------
6.Why delegation required for PostgreSQL?
Answer:Azure PostgreSQL Flexible Server requires full control over subnet for internal networking. Without delegation, deployment fails.

-------------------------------------------------------------------------------------------------------------
7.What is role of DNS(Domain name system)?
  Answer: The role of DNS is to translate a domain name into an IP address.
  In simple words, DNS works like a phonebook of the internet.
  Humans prefer to use easy-to-remember names, but computers communicate using IP addresses.

  For example, instead of using an IP address like: 10.0.2.4
  we use a domain name like: mydb.postgres.database.azure.com

  When a request is made, DNS converts this domain name into its corresponding IP address:
    mydb.postgres.database.azure.com → 10.0.2.4

  After that, the system uses the IP address to establish the connection.
  Here:
    10.0.2.4  => This is IP address of your specific service inside azure vnet.
    mydb      => This is your specific service i.e database inside azure Vnet.
    postgres.database.azure.com  => This is azure domain name.

    mydb.postgres.database.azure.com => This is Fully Qualified Domain Name corresponding to IP address. It is simply called as Hostname or Domain name.

-------------------------------------------------------------------------------------------------------------
8.If your application is deployed inside a private Virtual Network (VNet) and you need to call an external API, how will you enable outbound connectivity? What components are required and why?
Or How does an application in a private subnet access the internet?

Answer: If we need to call an external API, we must have a NAT Gateway or proper outbound configuration.
  Otherwise, the request may fail because all traffic is forced into the VNet and cannot go outside.

  When your application is inside a private network (VNet):
    It can talk to internal resources easily
    But it cannot access the internet directly

  So if your app tries to call something like:
    a payment API
    a third-party service
    any public API

  the request will fail.

  All outbound traffic is restricted and stays inside the VNet unless explicitly allowed.

  A NAT Gateway acts like an exit door to the internet.
    App inside VNet sends request
    NAT Gateway receives it
    NAT Gateway sends it to the internet
    Response comes back through NAT Gateway