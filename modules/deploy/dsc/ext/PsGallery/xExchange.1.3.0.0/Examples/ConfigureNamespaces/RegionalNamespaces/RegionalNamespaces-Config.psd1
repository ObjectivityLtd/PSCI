@{
    AllNodes = @(
        #Settings under 'NodeName = *' apply to all nodes.
        @{
            NodeName        = '*'

            #CertificateFile and Thumbprint are used for securing credentials. See:
            #http://blogs.msdn.com/b/powershell/archive/2014/01/31/want-to-secure-credentials-in-windows-powershell-desired-state-configuration.aspx
            
        }

        #Individual target nodes are defined next
        @{
            NodeName = 'e15-1'
            CASID    = 'Site1CAS'
        }

        @{
            NodeName = 'e15-2'
            CASID    = 'Site2CAS'
        }
    );

    #CAS settings that are unique per site will go in separate hash table entries.
    Site1CAS = @(
        @{
            ExternalNLBFqdn       = 'mail.mikelab.local'
            InternalNLBFqdn       = 'mail-site1.mikelab.local'
            AutoDiscoverSiteScope = 'Site1'
        }
    );

    Site2CAS = @(
        @{
            ExternalNLBFqdn       = 'mail.mikelab.local'
            InternalNLBFqdn       = 'mail-site2.mikelab.local'
            AutoDiscoverSiteScope = 'Site2'
        }
    );
}