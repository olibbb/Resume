using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $CosmosIn, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

Write-Host $Request.Headers.'client-ip'
Write-Host $Request.Headers.'user-agent'


# InputBinding SQL query to get count of rows : "SELECT count('id') as visitorCount from c"
if ($CosmosIn) {
    
    $visitorCount = $CosmosIn.visitorCount
    $guid = (new-guid).Guid

    #Create a new row with a guid (Add IP addresses later)
    Push-OutputBinding -name CosmosOut -Value @{
        id        = $guid
        userAgent = $Request.Headers.'user-agent'
        clientIp  = $Request.Headers.'client-ip'
    }

    $body = @{
        visitorCount = $visitorCount
        clientIp     = $Request.Headers.'client-ip'
    }
    
    Write-host $body

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ($body | ConvertTo-Json)
        })

}

else {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext])@{
        StatusCode = [HttpStatusCode]::NotFound
        Body       = "Cosmos DB input not Found"

    }
    
}


