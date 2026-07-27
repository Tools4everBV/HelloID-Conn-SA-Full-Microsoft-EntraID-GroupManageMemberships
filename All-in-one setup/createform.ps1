# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

#HelloID variables
#Note: when running this script inside HelloID; portalUrl and API credentials are provided automatically (generate and save API credentials first in your admin panel!)
$portalUrl = "https://CUSTOMER.helloid.com"
$apiKey = "API_KEY"
$apiSecret = "API_SECRET"
$delegatedFormAccessGroupNames = @("") #Only unique names are supported. Groups must exist!
$delegatedFormCategories = @("Entra ID","Group Management") #Only unique names are supported. Categories will be created if not exists
$script:debugLogging = $false #Default value: $false. If $true, the HelloID resource GUIDs will be shown in the logging
$script:duplicateForm = $false #Default value: $false. If $true, the HelloID resource names will be changed to import a duplicate Form
$script:duplicateFormSuffix = "_tmp" #the suffix will be added to all HelloID resource names to generate a duplicate form with different resource names

#The following HelloID Global variables are used by this form. No existing HelloID global variables will be overriden only new ones are created.
#NOTE: You can also update the HelloID Global variable values afterwards in the HelloID Admin Portal: https://<CUSTOMER>.helloid.com/admin/variablelibrary
$globalHelloIDVariables = [System.Collections.Generic.List[object]]@();

#Global variable #1 >> EntraIdAppId
$tmpName = @'
EntraIdAppId
'@ 
$tmpValue = ""
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});

#Global variable #2 >> EntraIdCertificateBase64String
$tmpName = @'
EntraIdCertificateBase64String
'@ 
$tmpValue = "" 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "True"});

#Global variable #3 >> EntraIdCertificatePassword
$tmpName = @'
EntraIdCertificatePassword
'@ 
$tmpValue = "" 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "True"});

#Global variable #4 >> EntraIdTenantId
$tmpName = @'
EntraIdTenantId
'@ 
$tmpValue = ""
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});


#make sure write-information logging is visual
$InformationPreference = "continue"

# Check for prefilled API Authorization header
if (-not [string]::IsNullOrEmpty($portalApiBasic)) {
    $script:headers = @{"authorization" = $portalApiBasic}
    Write-Information "Using prefilled API credentials"
} else {
    # Create authorization headers with HelloID API key
    $pair = "$apiKey" + ":" + "$apiSecret"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)
    $key = "Basic $base64"
    $script:headers = @{"authorization" = $Key}
    Write-Information "Using manual API credentials"
}

# Check for prefilled PortalBaseURL
if (-not [string]::IsNullOrEmpty($portalBaseUrl)) {
    $script:PortalBaseUrl = $portalBaseUrl
    Write-Information "Using prefilled PortalURL: $script:PortalBaseUrl"
} else {
    $script:PortalBaseUrl = $portalUrl
    Write-Information "Using manual PortalURL: $script:PortalBaseUrl"
}

# Define specific endpoint URI
$script:PortalBaseUrl = $script:PortalBaseUrl.trim("/") + "/"  

# Make sure to reveive an empty array using PowerShell Core
function ConvertFrom-Json-WithEmptyArray([string]$jsonString) {
    # Running in PowerShell Core?
    if($IsCoreCLR -eq $true){
        $r = [Object[]]($jsonString | ConvertFrom-Json -NoEnumerate)
        return ,$r  # Force return value to be an array using a comma
    } else {
        $r = [Object[]]($jsonString | ConvertFrom-Json)
        return ,$r  # Force return value to be an array using a comma
    }
}

function Invoke-HelloIDGlobalVariable {
    param(
        [parameter(Mandatory)][String]$Name,
        [parameter(Mandatory)][String][AllowEmptyString()]$Value,
        [parameter(Mandatory)][String]$Secret
    )

    $Name = $Name + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl + "api/v1/automation/variables/named/$Name")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false

        if ([string]::IsNullOrEmpty($response.automationVariableGuid)) {
            #Create Variable
            $body = @{
                name     = $Name;
                value    = $Value;
                secret   = $Secret;
                ItemType = 0;
            }    
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl + "api/v1/automation/variable")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $variableGuid = $response.automationVariableGuid

            Write-Information "Variable '$Name' created$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        } else {
            $variableGuid = $response.automationVariableGuid
            Write-Warning "Variable '$Name' already exists$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        }
    } catch {
        Write-Error "Variable '$Name', message: $_"
    }
}

function Invoke-HelloIDAutomationTask {
    param(
        [parameter(Mandatory)][String]$TaskName,
        [parameter(Mandatory)][String]$UseTemplate,
        [parameter(Mandatory)][String]$AutomationContainer,
        [parameter(Mandatory)][String][AllowEmptyString()]$Variables,
        [parameter(Mandatory)][String]$PowershellScript,
        [parameter()][String][AllowEmptyString()]$ObjectGuid,
        [parameter()][String][AllowEmptyString()]$ForceCreateTask,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $TaskName = $TaskName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl +"api/v1/automationtasks?search=$TaskName&container=$AutomationContainer")
        $responseRaw = (Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false) 
        $response = $responseRaw | Where-Object -filter {$_.name -eq $TaskName}

        if([string]::IsNullOrEmpty($response.automationTaskGuid) -or $ForceCreateTask -eq $true) {
            #Create Task

            $body = @{
                name                = $TaskName;
                useTemplate         = $UseTemplate;
                powerShellScript    = $PowershellScript;
                automationContainer = $AutomationContainer;
                objectGuid          = $ObjectGuid;
                variables           = (ConvertFrom-Json-WithEmptyArray($Variables));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl +"api/v1/automationtasks/powershell")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $taskGuid = $response.automationTaskGuid

            Write-Information "Powershell task '$TaskName' created$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        } else {
            #Get TaskGUID
            $taskGuid = $response.automationTaskGuid
            Write-Warning "Powershell task '$TaskName' already exists$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        }
    } catch {
        Write-Error "Powershell task '$TaskName', message: $_"
    }

    $returnObject.Value = $taskGuid
}

function Invoke-HelloIDDatasource {
    param(
        [parameter(Mandatory)][String]$DatasourceName,
        [parameter(Mandatory)][String]$DatasourceType,
        [parameter(Mandatory)][String][AllowEmptyString()]$DatasourceModel,
        [parameter()][String][AllowEmptyString()]$DatasourceStaticValue,
        [parameter()][String][AllowEmptyString()]$DatasourcePsScript,        
        [parameter()][String][AllowEmptyString()]$DatasourceInput,
        [parameter()][String][AllowEmptyString()]$AutomationTaskGuid,
        [parameter()][String][AllowEmptyString()]$DatasourceRunInCloud,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $DatasourceName = $DatasourceName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    $datasourceTypeName = switch($DatasourceType) { 
        "1" { "Native data source"; break} 
        "2" { "Static data source"; break} 
        "3" { "Task data source"; break} 
        "4" { "Powershell data source"; break}
    }

    try {
        $uri = ($script:PortalBaseUrl +"api/v1/datasource/named/$DatasourceName")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
    
        if([string]::IsNullOrEmpty($response.dataSourceGUID)) {
            #Create DataSource
            $body = @{
                name               = $DatasourceName;
                type               = $DatasourceType;
                model              = (ConvertFrom-Json-WithEmptyArray($DatasourceModel));
                automationTaskGUID = $AutomationTaskGuid;
                value              = (ConvertFrom-Json-WithEmptyArray($DatasourceStaticValue));
                script             = $DatasourcePsScript;
                input              = (ConvertFrom-Json-WithEmptyArray($DatasourceInput));
                runInCloud         = $DatasourceRunInCloud;
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100
    
            $uri = ($script:PortalBaseUrl +"api/v1/datasource")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            
            $datasourceGuid = $response.dataSourceGUID
            Write-Information "$datasourceTypeName '$DatasourceName' created$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        } else {
            #Get DatasourceGUID
            $datasourceGuid = $response.dataSourceGUID
            Write-Warning "$datasourceTypeName '$DatasourceName' already exists$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        }
    } catch {
        Write-Error "$datasourceTypeName '$DatasourceName', message: $_"
    }

    $returnObject.Value = $datasourceGuid
}

function Invoke-HelloIDDynamicForm {
    param(
        [parameter(Mandatory)][String]$FormName,
        [parameter(Mandatory)][String]$FormSchema,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $FormName = $FormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/forms/$FormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        } catch {
            $response = $null
        }

        if(([string]::IsNullOrEmpty($response.dynamicFormGUID)) -or ($response.isUpdated -eq $true)) {
            #Create Dynamic form
            $body = @{
                Name       = $FormName;
                FormSchema = (ConvertFrom-Json-WithEmptyArray($FormSchema));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl +"api/v1/forms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body

            $formGuid = $response.dynamicFormGUID
            Write-Information "Dynamic form '$formName' created$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        } else {
            $formGuid = $response.dynamicFormGUID
            Write-Warning "Dynamic form '$FormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        }
    } catch {
        Write-Error "Dynamic form '$FormName', message: $_"
    }

    $returnObject.Value = $formGuid
}


function Invoke-HelloIDDelegatedForm {
    param(
        [parameter(Mandatory)][String]$DelegatedFormName,
        [parameter(Mandatory)][String]$DynamicFormGuid,
        [parameter()][Array][AllowEmptyString()]$AccessGroups,
        [parameter()][String][AllowEmptyString()]$Categories,
        [parameter(Mandatory)][String]$UseFaIcon,
        [parameter()][String][AllowEmptyString()]$FaIcon,
        [parameter()][String][AllowEmptyString()]$task,
        [parameter(Mandatory)][Ref]$returnObject
    )
    $delegatedFormCreated = $false
    $DelegatedFormName = $DelegatedFormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms/$DelegatedFormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        } catch {
            $response = $null
        }

        if([string]::IsNullOrEmpty($response.delegatedFormGUID)) {
            #Create DelegatedForm
            $body = @{
                name            = $DelegatedFormName;
                dynamicFormGUID = $DynamicFormGuid;
                isEnabled       = "True";
                useFaIcon       = $UseFaIcon;
                faIcon          = $FaIcon;
                task            = ConvertFrom-Json -inputObject $task;
            }
            if(-not[String]::IsNullOrEmpty($AccessGroups)) { 
                $body += @{
                    accessGroups    = (ConvertFrom-Json-WithEmptyArray($AccessGroups));
                }
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body

            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Information "Delegated form '$DelegatedFormName' created$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
            $delegatedFormCreated = $true

            $bodyCategories = $Categories
            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms/$delegatedFormGuid/categories")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $bodyCategories
            Write-Information "Delegated form '$DelegatedFormName' updated with categories"
        } else {
            #Get delegatedFormGUID
            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Warning "Delegated form '$DelegatedFormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
        }
    } catch {
        Write-Error "Delegated form '$DelegatedFormName', message: $_"
    }

    $returnObject.value.guid = $delegatedFormGuid
    $returnObject.value.created = $delegatedFormCreated
}

<# Begin: HelloID Global Variables #>
foreach ($item in $globalHelloIDVariables) {
	Invoke-HelloIDGlobalVariable -Name $item.name -Value $item.value -Secret $item.secret 
}
<# End: HelloID Global Variables #>


<# Begin: HelloID Data sources #>
<# Begin: DataSource "entra-id-group-manage-memberships | Entra-ID-Get-Groups-Wildcard-DisplayName-Mail-Description" #>
$tmpPsScript = @'
# Variables configured in form
$searchValue = $datasource.searchvalue
if ($searchValue -eq "*") {
    $filter = "`$filter=((groupTypes/any(c:c+eq+'Unified')) or (NOT(groupTypes/any(c:c+eq+'DynamicMembership')) and onPremisesSyncEnabled eq null and mailEnabled eq false and securityEnabled eq true)) and NOT(resourceProvisioningOptions/any(x:x eq 'Team'))"
}
else {
    $filter = "`$search=`"displayName:$searchValue`" OR `"description:$searchValue`" OR `"mail:$searchValue`"&`$filter=((groupTypes/any(c:c+eq+'Unified')) or (NOT(groupTypes/any(c:c+eq+'DynamicMembership')) and onPremisesSyncEnabled eq null and mailEnabled eq false and securityEnabled eq true)) and NOT(resourceProvisioningOptions/any(x:x eq 'Team'))"
}

# Global variables
# Outcommented as these are set from Global Variables
# $EntraIdTenantId = ""
# $EntraIdAppId = ""
# $EntraIdCertificateBase64String = ""
# $EntraIdCertificatePassword = ""

# Fixed values
$propertiesToSelect = @("id", "displayName", "description", "mail") # Properties to select from Microsoft Graph API, comma separated

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
function Resolve-MicrosoftGraphAPIError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json -ErrorAction Stop)
            if ($errorDetailsObject.error_description) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.error_description
            }
            elseif ($errorDetailsObject.error.message) {
                $httpErrorObj.FriendlyMessage = "$($errorDetailsObject.error.code): $($errorDetailsObject.error.message)"
            }
            elseif ($errorDetailsObject.error.details.message) {
                $httpErrorObj.FriendlyMessage = "$($errorDetailsObject.error.details.code): $($errorDetailsObject.error.details.message)"
            }
            else {
                $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
            }
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}


function Get-MSEntraAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Certificate,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $AppId,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $TenantId
    )
    try {
        # Get the DER encoded bytes of the certificate
        $derBytes = $Certificate.RawData

        # Compute the SHA-256 hash of the DER encoded bytes
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha256.ComputeHash($derBytes)
        $base64Thumbprint = [System.Convert]::ToBase64String($hashBytes).Replace('+', '-').Replace('/', '_').Replace('=', '')

        # Create a JWT (JSON Web Token) header
        $header = @{
            'alg'      = 'RS256'
            'typ'      = 'JWT'
            'x5t#S256' = $base64Thumbprint
        } | ConvertTo-Json
        $base64Header = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($header))

        # Calculate the Unix timestamp (seconds since 1970-01-01T00:00:00Z) for 'exp', 'nbf' and 'iat'
        $currentUnixTimestamp = [math]::Round(((Get-Date).ToUniversalTime() - ([datetime]'1970-01-01T00:00:00Z').ToUniversalTime()).TotalSeconds)

        # Create a JWT payload
        $payload = [Ordered]@{
            'iss' = "$($AppId)"
            'sub' = "$($AppId)"
            'aud' = "https://login.microsoftonline.com/$($TenantId)/oauth2/token"
            'exp' = ($currentUnixTimestamp + 3600) # Expires in 1 hour
            'nbf' = ($currentUnixTimestamp - 300) # Not before 5 minutes ago
            'iat' = $currentUnixTimestamp
            'jti' = [Guid]::NewGuid().ToString()
        } | ConvertTo-Json
        $base64Payload = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payload)).Replace('+', '-').Replace('/', '_').Replace('=', '')

        # Extract the private key from the certificate
        $rsaPrivate = $Certificate.PrivateKey
        $rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new()
        $rsa.ImportParameters($rsaPrivate.ExportParameters($true))

        # Sign the JWT
        $signatureInput = "$base64Header.$base64Payload"
        $signature = $rsa.SignData([Text.Encoding]::UTF8.GetBytes($signatureInput), 'SHA256')
        $base64Signature = [System.Convert]::ToBase64String($signature).Replace('+', '-').Replace('/', '_').Replace('=', '')

        # Create the JWT token
        $jwtToken = "$($base64Header).$($base64Payload).$($base64Signature)"

        $createEntraAccessTokenBody = @{
            grant_type            = 'client_credentials'
            client_id             = $AppId
            client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
            client_assertion      = $jwtToken
            resource              = 'https://graph.microsoft.com'
        }

        $createEntraAccessTokenSplatParams = @{
            Uri         = "https://login.microsoftonline.com/$($TenantId)/oauth2/token"
            Body        = $createEntraAccessTokenBody
            Method      = 'POST'
            ContentType = 'application/x-www-form-urlencoded'
            Verbose     = $false
            ErrorAction = 'Stop'
        }

        $createEntraAccessTokenResponse = Invoke-RestMethod @createEntraAccessTokenSplatParams
        Write-Output $createEntraAccessTokenResponse.access_token
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Get-MSEntraCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CertificateBase64String,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CertificatePassword
    )
    try {
        $rawCertificate = [system.convert]::FromBase64String($CertificateBase64String)
        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawCertificate, $CertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
        Write-Output $certificate
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion functions

try {
    # Convert base64 certificate string to certificate object
    $actionMessage = "converting base64 certificate string to certificate object"
    $certificate = Get-MSEntraCertificate -CertificateBase64String $EntraIdCertificateBase64String -CertificatePassword $EntraIdCertificatePassword
    Write-Verbose "Converted base64 certificate string to certificate object"

    # Create access token
    $actionMessage = "creating access token"
    $entraToken = Get-MSEntraAccessToken -Certificate $certificate -AppId $EntraIdAppId -TenantId $EntraIdTenantId
    Write-Verbose "Created access token"

    # Create headers
    $actionMessage = "creating headers"
    $headers = @{
        "Authorization"    = "Bearer $($entraToken)"
        "Accept"           = "application/json"
        "Content-Type"     = "application/json"
        "ConsistencyLevel" = "eventual" # Needed to filter on specific attributes (https://docs.microsoft.com/en-us/graph/aad-advanced-queries)
    }
    Write-Verbose "Created headers"

    # Get Microsoft Entra ID Groups
    # API docs: https://learn.microsoft.com/en-us/graph/api/group-list?view=graph-rest-1.0&tabs=http
    $actionMessage = "querying Microsoft Entra ID Groups matching search value [$searchValue]"
    $microsoftEntraIDGroups = [System.Collections.ArrayList]@()
    do {
        $getMicrosoftEntraIDGroupsSplatParams = @{
            Uri         = "https://graph.microsoft.com/v1.0/groups?$filter&`$select=$($propertiesToSelect -join ',')&`$top=999&`$count=true"
            Headers     = $headers
            Method      = "GET"
            Verbose     = $false
            ErrorAction = "Stop"
        }
        if (-not[string]::IsNullOrEmpty($getMicrosoftEntraIDGroupsResponse.'@odata.nextLink')) {
            $getMicrosoftEntraIDGroupsSplatParams["Uri"] = $getMicrosoftEntraIDGroupsResponse.'@odata.nextLink'
        }
        
        $getMicrosoftEntraIDGroupsResponse = $null
        $getMicrosoftEntraIDGroupsResponse = Invoke-RestMethod @getMicrosoftEntraIDGroupsSplatParams
    
        # Select only specified properties to limit memory usage
        $getMicrosoftEntraIDGroupsResponse.Value = $getMicrosoftEntraIDGroupsResponse.Value | Select-Object $propertiesToSelect

        if ($getMicrosoftEntraIDGroupsResponse.Value -is [array]) {
            [void]$microsoftEntraIDGroups.AddRange($getMicrosoftEntraIDGroupsResponse.Value)
        }
        else {
            [void]$microsoftEntraIDGroups.Add($getMicrosoftEntraIDGroupsResponse.Value)
        }
    } while (-not[string]::IsNullOrEmpty($getMicrosoftEntraIDGroupsResponse.'@odata.nextLink'))
    Write-Information "Queried Microsoft Entra ID Groups matching search value [$searchValue]. Result count: $(($microsoftEntraIDGroups | Measure-Object).Count)"

    # Send results to HelloID
    $actionMessage = "sending results to HelloID"
    $microsoftEntraIDGroups | ForEach-Object {
        Write-Output $_
    }
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-MicrosoftGraphAPIError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    Write-Warning $warningMessage
    Write-Error $auditMessage
}
'@ 
$tmpModel = @'
[{"key":"id","type":0},{"key":"displayName","type":0},{"key":"description","type":0},{"key":"mail","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"searchValue","type":0,"options":1}]
'@ 
$dataSourceGuid_0 = [PSCustomObject]@{} 
$dataSourceGuid_0_Name = @'
entra-id-group-manage-memberships | Entra-ID-Get-Groups-Wildcard-DisplayName-Mail-Description
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_0_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "True" -returnObject ([Ref]$dataSourceGuid_0) 
<# End: DataSource "entra-id-group-manage-memberships | Entra-ID-Get-Groups-Wildcard-DisplayName-Mail-Description" #>

<# Begin: DataSource "entra-id-group-manage-memberships | Entra-ID-Get-All-Users" #>
$tmpPsScript = @'
# Global variables
# Outcommented as these are set from Global Variables
# $EntraIdTenantId = ""
# $EntraIdAppId = ""
# $EntraIdCertificateBase64String = ""
# $EntraIdCertificatePassword = ""

# Fixed values
$filter = "`$filter=displayName ne null"
$propertiesToSelect = @("id", "displayName", "mail", "userPrincipalName", "employeeId", "accountEnabled") # Properties to select from Microsoft Graph API, comma separated

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
function Resolve-MicrosoftGraphAPIError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json -ErrorAction Stop)
            if ($errorDetailsObject.error_description) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.error_description
            }
            elseif ($errorDetailsObject.error.message) {
                $httpErrorObj.FriendlyMessage = "$($errorDetailsObject.error.code): $($errorDetailsObject.error.message)"
            }
            elseif ($errorDetailsObject.error.details.message) {
                $httpErrorObj.FriendlyMessage = "$($errorDetailsObject.error.details.code): $($errorDetailsObject.error.details.message)"
            }
            else {
                $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
            }
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}


function Get-MSEntraAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Certificate,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $AppId,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $TenantId
    )
    try {
        # Get the DER encoded bytes of the certificate
        $derBytes = $Certificate.RawData

        # Compute the SHA-256 hash of the DER encoded bytes
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha256.ComputeHash($derBytes)
        $base64Thumbprint = [System.Convert]::ToBase64String($hashBytes).Replace('+', '-').Replace('/', '_').Replace('=', '')

        # Create a JWT (JSON Web Token) header
        $header = @{
            'alg'      = 'RS256'
            'typ'      = 'JWT'
            'x5t#S256' = $base64Thumbprint
        } | ConvertTo-Json
        $base64Header = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($header))

        # Calculate the Unix timestamp (seconds since 1970-01-01T00:00:00Z) for 'exp', 'nbf' and 'iat'
        $currentUnixTimestamp = [math]::Round(((Get-Date).ToUniversalTime() - ([datetime]'1970-01-01T00:00:00Z').ToUniversalTime()).TotalSeconds)

        # Create a JWT payload
        $payload = [Ordered]@{
            'iss' = "$($AppId)"
            'sub' = "$($AppId)"
            'aud' = "https://login.microsoftonline.com/$($TenantId)/oauth2/token"
            'exp' = ($currentUnixTimestamp + 3600) # Expires in 1 hour
            'nbf' = ($currentUnixTimestamp - 300) # Not before 5 minutes ago
            'iat' = $currentUnixTimestamp
            'jti' = [Guid]::NewGuid().ToString()
        } | ConvertTo-Json
        $base64Payload = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payload)).Replace('+', '-').Replace('/', '_').Replace('=', '')

        # Extract the private key from the certificate
        $rsaPrivate = $Certificate.PrivateKey
        $rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new()
        $rsa.ImportParameters($rsaPrivate.ExportParameters($true))

        # Sign the JWT
        $signatureInput = "$base64Header.$base64Payload"
        $signature = $rsa.SignData([Text.Encoding]::UTF8.GetBytes($signatureInput), 'SHA256')
        $base64Signature = [System.Convert]::ToBase64String($signature).Replace('+', '-').Replace('/', '_').Replace('=', '')

        # Create the JWT token
        $jwtToken = "$($base64Header).$($base64Payload).$($base64Signature)"

        $createEntraAccessTokenBody = @{
            grant_type            = 'client_credentials'
            client_id             = $AppId
            client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
            client_assertion      = $jwtToken
            resource              = 'https://graph.microsoft.com'
        }

        $createEntraAccessTokenSplatParams = @{
            Uri         = "https://login.microsoftonline.com/$($TenantId)/oauth2/token"
            Body        = $createEntraAccessTokenBody
            Method      = 'POST'
            ContentType = 'application/x-www-form-urlencoded'
            Verbose     = $false
            ErrorAction = 'Stop'
        }

        $createEntraAccessTokenResponse = Invoke-RestMethod @createEntraAccessTokenSplatParams
        Write-Output $createEntraAccessTokenResponse.access_token
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Get-MSEntraCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CertificateBase64String,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CertificatePassword
    )
    try {
        $rawCertificate = [system.convert]::FromBase64String($CertificateBase64String)
        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawCertificate, $CertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
        Write-Output $certificate
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion functions

try {
    # Convert base64 certificate string to certificate object
    $actionMessage = "converting base64 certificate string to certificate object"
    $certificate = Get-MSEntraCertificate -CertificateBase64String $EntraIdCertificateBase64String -CertificatePassword $EntraIdCertificatePassword
    Write-Verbose "Converted base64 certificate string to certificate object"

    # Create access token
    $actionMessage = "creating access token"
    $entraToken = Get-MSEntraAccessToken -Certificate $certificate -AppId $EntraIdAppId -TenantId $EntraIdTenantId
    Write-Verbose "Created access token"

    # Create headers
    $actionMessage = "creating headers"
    $headers = @{
        "Authorization"    = "Bearer $($entraToken)"
        "Accept"           = "application/json"
        "Content-Type"     = "application/json"
        "ConsistencyLevel" = "eventual" # Needed to filter on specific attributes (https://docs.microsoft.com/en-us/graph/aad-advanced-queries)
    }
    Write-Verbose "Created headers"

    # Get Microsoft Entra ID Users
    # API docs: https://learn.microsoft.com/en-us/graph/api/user-list?view=graph-rest-1.0&tabs=http
    $actionMessage = "querying all Microsoft Entra ID Users"
    $microsoftEntraIDUsers = [System.Collections.ArrayList]@()
    do {
        $getMicrosoftEntraIDUsersSplatParams = @{
            Uri         = "https://graph.microsoft.com/v1.0/users?$filter&`$select=$($propertiesToSelect -join ',')&`$top=999&`$count=true"
            Headers     = $headers
            Method      = "GET"
            Verbose     = $false
            ErrorAction = "Stop"
        }
        if (-not[string]::IsNullOrEmpty($getMicrosoftEntraIDUsersResponse.'@odata.nextLink')) {
            $getMicrosoftEntraIDUsersSplatParams["Uri"] = $getMicrosoftEntraIDUsersResponse.'@odata.nextLink'
        }
        
        $getMicrosoftEntraIDUsersResponse = $null
        $getMicrosoftEntraIDUsersResponse = Invoke-RestMethod @getMicrosoftEntraIDUsersSplatParams
    
        # Select only specified properties to limit memory usage
        $getMicrosoftEntraIDUsersResponse.Value = $getMicrosoftEntraIDUsersResponse.Value | Select-Object $propertiesToSelect

        if ($getMicrosoftEntraIDUsersResponse.Value -is [array]) {
            [void]$microsoftEntraIDUsers.AddRange($getMicrosoftEntraIDUsersResponse.Value)
        }
        else {
            [void]$microsoftEntraIDUsers.Add($getMicrosoftEntraIDUsersResponse.Value)
        }
    } while (-not[string]::IsNullOrEmpty($getMicrosoftEntraIDUsersResponse.'@odata.nextLink'))
    Write-Information "Queried all Microsoft Entra ID Users. Result count: $(($microsoftEntraIDUsers | Measure-Object).Count)"

    # Send results to HelloID
    $actionMessage = "sending results to HelloID"
    $microsoftEntraIDUsers | ForEach-Object {
        # Add displayValue property as HelloID can only display a single property
        $_ | Add-Member -NotePropertyName 'displayValue' -NotePropertyValue "$($_.displayName) [$($_.userPrincipalName)]" -Force
        Write-Output $_
    }
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-MicrosoftGraphAPIError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    Write-Warning $warningMessage
    Write-Error $auditMessage
}
'@ 
$tmpModel = @'
[{"key":"id","type":0},{"key":"displayName","type":0},{"key":"mail","type":0},{"key":"userPrincipalName","type":0},{"key":"employeeId","type":0},{"key":"accountEnabled","type":0},{"key":"displayValue","type":0}]
'@ 
$tmpInput = @'
[]
'@ 
$dataSourceGuid_2 = [PSCustomObject]@{} 
$dataSourceGuid_2_Name = @'
entra-id-group-manage-memberships | Entra-ID-Get-All-Users
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_2_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "True" -returnObject ([Ref]$dataSourceGuid_2) 
<# End: DataSource "entra-id-group-manage-memberships | Entra-ID-Get-All-Users" #>

<# Begin: DataSource "entra-id-group-manage-memberships | Entra-ID-Get-GroupMembers" #>
$tmpPsScript = @'
# Variables configured in form
$group = $datasource.selectedGroup

# Global variables
# Outcommented as these are set from Global Variables
# $EntraIdTenantId = ""
# $EntraIdAppId = ""
# $EntraIdCertificateBase64String = ""
# $EntraIdCertificatePassword = ""

# Fixed values
$propertiesToSelect = @("id", "displayName", "userPrincipalName", "mail") # Properties to select from Microsoft Graph API, comma separated

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
function Resolve-MicrosoftGraphAPIError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json -ErrorAction Stop)
            if ($errorDetailsObject.error_description) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.error_description
            }
            elseif ($errorDetailsObject.error.message) {
                $httpErrorObj.FriendlyMessage = "$($errorDetailsObject.error.code): $($errorDetailsObject.error.message)"
            }
            elseif ($errorDetailsObject.error.details.message) {
                $httpErrorObj.FriendlyMessage = "$($errorDetailsObject.error.details.code): $($errorDetailsObject.error.details.message)"
            }
            else {
                $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
            }
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}


function Get-MSEntraAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Certificate,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $AppId,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $TenantId
    )
    try {
        # Get the DER encoded bytes of the certificate
        $derBytes = $Certificate.RawData

        # Compute the SHA-256 hash of the DER encoded bytes
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha256.ComputeHash($derBytes)
        $base64Thumbprint = [System.Convert]::ToBase64String($hashBytes).Replace('+', '-').Replace('/', '_').Replace('=', '')

        # Create a JWT (JSON Web Token) header
        $header = @{
            'alg'      = 'RS256'
            'typ'      = 'JWT'
            'x5t#S256' = $base64Thumbprint
        } | ConvertTo-Json
        $base64Header = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($header))

        # Calculate the Unix timestamp (seconds since 1970-01-01T00:00:00Z) for 'exp', 'nbf' and 'iat'
        $currentUnixTimestamp = [math]::Round(((Get-Date).ToUniversalTime() - ([datetime]'1970-01-01T00:00:00Z').ToUniversalTime()).TotalSeconds)

        # Create a JWT payload
        $payload = [Ordered]@{
            'iss' = "$($AppId)"
            'sub' = "$($AppId)"
            'aud' = "https://login.microsoftonline.com/$($TenantId)/oauth2/token"
            'exp' = ($currentUnixTimestamp + 3600) # Expires in 1 hour
            'nbf' = ($currentUnixTimestamp - 300) # Not before 5 minutes ago
            'iat' = $currentUnixTimestamp
            'jti' = [Guid]::NewGuid().ToString()
        } | ConvertTo-Json
        $base64Payload = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payload)).Replace('+', '-').Replace('/', '_').Replace('=', '')

        # Extract the private key from the certificate
        $rsaPrivate = $Certificate.PrivateKey
        $rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new()
        $rsa.ImportParameters($rsaPrivate.ExportParameters($true))

        # Sign the JWT
        $signatureInput = "$base64Header.$base64Payload"
        $signature = $rsa.SignData([Text.Encoding]::UTF8.GetBytes($signatureInput), 'SHA256')
        $base64Signature = [System.Convert]::ToBase64String($signature).Replace('+', '-').Replace('/', '_').Replace('=', '')

        # Create the JWT token
        $jwtToken = "$($base64Header).$($base64Payload).$($base64Signature)"

        $createEntraAccessTokenBody = @{
            grant_type            = 'client_credentials'
            client_id             = $AppId
            client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
            client_assertion      = $jwtToken
            resource              = 'https://graph.microsoft.com'
        }

        $createEntraAccessTokenSplatParams = @{
            Uri         = "https://login.microsoftonline.com/$($TenantId)/oauth2/token"
            Body        = $createEntraAccessTokenBody
            Method      = 'POST'
            ContentType = 'application/x-www-form-urlencoded'
            Verbose     = $false
            ErrorAction = 'Stop'
        }

        $createEntraAccessTokenResponse = Invoke-RestMethod @createEntraAccessTokenSplatParams
        Write-Output $createEntraAccessTokenResponse.access_token
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Get-MSEntraCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CertificateBase64String,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CertificatePassword
    )
    try {
        $rawCertificate = [system.convert]::FromBase64String($CertificateBase64String)
        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawCertificate, $CertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
        Write-Output $certificate
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion functions

try {
    # Convert base64 certificate string to certificate object
    $actionMessage = "converting base64 certificate string to certificate object"
    $certificate = Get-MSEntraCertificate -CertificateBase64String $EntraIdCertificateBase64String -CertificatePassword $EntraIdCertificatePassword
    Write-Verbose "Converted base64 certificate string to certificate object"

    # Create access token
    $actionMessage = "creating access token"
    $entraToken = Get-MSEntraAccessToken -Certificate $certificate -AppId $EntraIdAppId -TenantId $EntraIdTenantId
    Write-Verbose "Created access token"

    # Create headers
    $actionMessage = "creating headers"
    $headers = @{
        "Authorization"    = "Bearer $($entraToken)"
        "Accept"           = "application/json"
        "Content-Type"     = "application/json"
        "ConsistencyLevel" = "eventual" # Needed to filter on specific attributes (https://docs.microsoft.com/en-us/graph/aad-advanced-queries)
    }
    Write-Verbose "Created headers"

    # Get Microsoft Entra ID Group Members
    # API docs: https://learn.microsoft.com/en-us/graph/api/group-list-members?view=graph-rest-1.0&tabs=http
    $actionMessage = "querying members of Microsoft Entra ID Group [$($group.displayName)] with ID [$($group.id)]"
    $microsoftEntraIDGroupMembers = [System.Collections.ArrayList]@()
    do {
        $getMicrosoftEntraIDGroupMembersSplatParams = @{
            Uri         = "https://graph.microsoft.com/v1.0/groups/$($group.id)/members?`$select=$($propertiesToSelect -join ',')&`$top=999&`$count=true"
            Headers     = $headers
            Method      = "GET"
            Verbose     = $false
            ErrorAction = "Stop"
        }
        if (-not[string]::IsNullOrEmpty($getMicrosoftEntraIDGroupMembersResponse.'@odata.nextLink')) {
            $getMicrosoftEntraIDGroupMembersSplatParams["Uri"] = $getMicrosoftEntraIDGroupMembersResponse.'@odata.nextLink'
        }
        
        $getMicrosoftEntraIDGroupMembersResponse = $null
        $getMicrosoftEntraIDGroupMembersResponse = Invoke-RestMethod @getMicrosoftEntraIDGroupMembersSplatParams
    
        # Select only specified properties to limit memory usage
        $getMicrosoftEntraIDGroupMembersResponse.Value = $getMicrosoftEntraIDGroupMembersResponse.Value | Select-Object $propertiesToSelect

        if ($getMicrosoftEntraIDGroupMembersResponse.Value -is [array]) {
            [void]$microsoftEntraIDGroupMembers.AddRange($getMicrosoftEntraIDGroupMembersResponse.Value)
        }
        else {
            [void]$microsoftEntraIDGroupMembers.Add($getMicrosoftEntraIDGroupMembersResponse.Value)
        }
    } while (-not[string]::IsNullOrEmpty($getMicrosoftEntraIDGroupMembersResponse.'@odata.nextLink'))
    Write-Information "Queried members of Microsoft Entra ID Group [$($group.displayName)] with ID [$($group.id)]. Result count: $(($microsoftEntraIDGroupMembers | Measure-Object).Count)"

    # Send results to HelloID
    $actionMessage = "sending results to HelloID"
    if ($microsoftEntraIDGroupMembers) {
        $microsoftEntraIDGroupMembers | ForEach-Object {
            # Add displayValue property as HelloID can only display a single property
            $_ | Add-Member -NotePropertyName 'displayValue' -NotePropertyValue "$($_.displayName) [$($_.userPrincipalName)]" -Force
            Write-Output $_
        }
    }
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-MicrosoftGraphAPIError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    Write-Warning $warningMessage
    Write-Error $auditMessage
}
'@ 
$tmpModel = @'
[{"key":"id","type":0},{"key":"displayName","type":0},{"key":"userPrincipalName","type":0},{"key":"mail","type":0},{"key":"displayValue","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"selectedGroup","type":0,"options":1}]
'@ 
$dataSourceGuid_1 = [PSCustomObject]@{} 
$dataSourceGuid_1_Name = @'
entra-id-group-manage-memberships | Entra-ID-Get-GroupMembers
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_1_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "True" -returnObject ([Ref]$dataSourceGuid_1) 
<# End: DataSource "entra-id-group-manage-memberships | Entra-ID-Get-GroupMembers" #>
<# End: HelloID Data sources #>

<# Begin: Dynamic Form "Entra ID Group - Manage memberships" #>
$tmpSchema = @"
[{"key":"searchfieldGroup","templateOptions":{"label":"Search field (wildcard search in Display name, description and mail)","placeholder":"Display name, description, or mail (use * to search all groups)","required":true},"type":"input","summaryVisibility":"Hide element","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"group","templateOptions":{"label":"Select group","grid":{"columns":[{"headerName":"Display Name","field":"displayName"},{"headerName":"Description","field":"description"},{"headerName":"Mail","field":"mail"},{"headerName":"ID","field":"id"}],"height":300,"rowSelection":"single"},"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_0","input":{"propertyInputs":[{"propertyName":"searchValue","otherFieldValue":{"otherFieldKey":"searchfieldGroup"}}]}},"useFilter":true,"useDefault":false,"allowCsvDownload":true,"required":true},"type":"grid","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":true},{"key":"groupMemberships","templateOptions":{"label":"Manage group memberships","required":false,"filterable":true,"useDataSource":true,"dualList":{"options":[{"guid":"75ea2890-88f8-4851-b202-626123054e14","Name":"Apple"},{"guid":"0607270d-83e2-4574-9894-0b70011b663f","Name":"Pear"},{"guid":"1ef6fe01-3095-4614-a6db-7c8cd416ae3b","Name":"Orange"}],"optionKeyProperty":"id","optionDisplayProperty":"displayValue","labelLeft":"All users","labelRight":"Current group members"},"destinationDataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_1","input":{"propertyInputs":[{"propertyName":"selectedGroup","otherFieldValue":{"otherFieldKey":"group"}}]}},"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_2","input":{"propertyInputs":[]}}},"hideExpression":"!model[\"group\"]","type":"duallist","summaryVisibility":"Show","sourceDataSourceIdentifierSuffix":"source-datasource","destinationDataSourceIdentifierSuffix":"destination-datasource","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false}]
"@ 

$dynamicFormGuid = [PSCustomObject]@{} 
$dynamicFormName = @'
Entra ID Group - Manage memberships
'@ 
Invoke-HelloIDDynamicForm -FormName $dynamicFormName -FormSchema $tmpSchema  -returnObject ([Ref]$dynamicFormGuid) 
<# END: Dynamic Form #>

<# Begin: Delegated Form Access Groups and Categories #>
$delegatedFormAccessGroupGuids = @()
if(-not[String]::IsNullOrEmpty($delegatedFormAccessGroupNames)){
    foreach($group in $delegatedFormAccessGroupNames) {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/groups/$group")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
            $delegatedFormAccessGroupGuid = $response.groupGuid
            $delegatedFormAccessGroupGuids += $delegatedFormAccessGroupGuid
        
            Write-Information "HelloID (access)group '$group' successfully found$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormAccessGroupGuid })"
        } catch {
            Write-Error "HelloID (access)group '$group', message: $_"
        }
    }
    if($null -ne $delegatedFormAccessGroupGuids){
        $delegatedFormAccessGroupGuids = ($delegatedFormAccessGroupGuids | Select-Object -Unique | ConvertTo-Json -Depth 100 -Compress)
    }
}

$delegatedFormCategoryGuids = @()
foreach($category in $delegatedFormCategories) {
    try {
        $uri = ($script:PortalBaseUrl +"api/v1/delegatedformcategories/$category")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        $response = $response | Where-Object {$_.name.en -eq $category}
    
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid
    
        Write-Information "HelloID Delegated Form category '$category' successfully found$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    } catch {
        Write-Warning "HelloID Delegated Form category '$category' not found"
        $body = @{
            name = @{"en" = $category};
        }
        $body = ConvertTo-Json -InputObject $body -Depth 100

        $uri = ($script:PortalBaseUrl +"api/v1/delegatedformcategories")
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid

        Write-Information "HelloID Delegated Form category '$category' successfully created$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    }
}
$delegatedFormCategoryGuids = (ConvertTo-Json -InputObject $delegatedFormCategoryGuids -Depth 100 -Compress)
<# End: Delegated Form Access Groups and Categories #>

<# Begin: Delegated Form #>
$delegatedFormRef = [PSCustomObject]@{guid = $null; created = $null} 
$delegatedFormName = @'
Entra ID Group - Manage memberships
'@
$tmpTask = @'
{"name":"Entra ID Group - Manage memberships","script":"# Variables configured in form\r\n$group = $form.group\r\n$usersToAdd = $form.groupMemberships.leftToRight\r\n$usersToRemove = $form.groupMemberships.RightToLeft\r\n\r\n# Global variables\r\n# Outcommented as these are set from Global Variables\r\n# $EntraIdTenantId = \"\"\r\n# $EntraIdAppId = \"\"\r\n# $EntraIdCertificateBase64String = \"\"\r\n# $EntraIdCertificatePassword = \"\"\r\n\r\n# Enable TLS1.2\r\n[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12\r\n\r\n# Set debug logging\r\n$VerbosePreference = \"SilentlyContinue\"\r\n$InformationPreference = \"Continue\"\r\n$WarningPreference = \"Continue\"\r\n\r\n#region functions\r\nfunction Resolve-MicrosoftGraphAPIError {\r\n    [CmdletBinding()]\r\n    param (\r\n        [Parameter(Mandatory)]\r\n        [object]\r\n        $ErrorObject\r\n    )\r\n    process {\r\n        $httpErrorObj = [PSCustomObject]@{\r\n            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber\r\n            Line             = $ErrorObject.InvocationInfo.Line\r\n            ErrorDetails     = $ErrorObject.Exception.Message\r\n            FriendlyMessage  = $ErrorObject.Exception.Message\r\n        }\r\n        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {\r\n            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message\r\n        }\r\n        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {\r\n            if ($null -ne $ErrorObject.Exception.Response) {\r\n                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()\r\n                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {\r\n                    $httpErrorObj.ErrorDetails = $streamReaderResponse\r\n                }\r\n            }\r\n        }\r\n        try {\r\n            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json -ErrorAction Stop)\r\n            if ($errorDetailsObject.error_description) {\r\n                $httpErrorObj.FriendlyMessage = $errorDetailsObject.error_description\r\n            }\r\n            elseif ($errorDetailsObject.error.message) {\r\n                $httpErrorObj.FriendlyMessage = \"$($errorDetailsObject.error.code): $($errorDetailsObject.error.message)\"\r\n            }\r\n            elseif ($errorDetailsObject.error.details.message) {\r\n                $httpErrorObj.FriendlyMessage = \"$($errorDetailsObject.error.details.code): $($errorDetailsObject.error.details.message)\"\r\n            }\r\n            else {\r\n                $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails\r\n            }\r\n        }\r\n        catch {\r\n            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails\r\n        }\r\n        Write-Output $httpErrorObj\r\n    }\r\n}\r\n\r\nfunction Get-MSEntraAccessToken {\r\n    [CmdletBinding()]\r\n    param(\r\n        [Parameter(Mandatory)]\r\n        [ValidateNotNull()]\r\n        $Certificate,\r\n        \r\n        [Parameter(Mandatory)]\r\n        [ValidateNotNullOrEmpty()]\r\n        [string]\r\n        $AppId,\r\n        \r\n        [Parameter(Mandatory)]\r\n        [ValidateNotNullOrEmpty()]\r\n        [string]\r\n        $TenantId\r\n    )\r\n    try {\r\n        # Get the DER encoded bytes of the certificate\r\n        $derBytes = $Certificate.RawData\r\n\r\n        # Compute the SHA-256 hash of the DER encoded bytes\r\n        $sha256 = [System.Security.Cryptography.SHA256]::Create()\r\n        $hashBytes = $sha256.ComputeHash($derBytes)\r\n        $base64Thumbprint = [System.Convert]::ToBase64String($hashBytes).Replace('+', '-').Replace('/', '_').Replace('=', '')\r\n\r\n        # Create a JWT (JSON Web Token) header\r\n        $header = @{\r\n            'alg'      = 'RS256'\r\n            'typ'      = 'JWT'\r\n            'x5t#S256' = $base64Thumbprint\r\n        } | ConvertTo-Json\r\n        $base64Header = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($header))\r\n\r\n        # Calculate the Unix timestamp (seconds since 1970-01-01T00:00:00Z) for 'exp', 'nbf' and 'iat'\r\n        $currentUnixTimestamp = [math]::Round(((Get-Date).ToUniversalTime() - ([datetime]'1970-01-01T00:00:00Z').ToUniversalTime()).TotalSeconds)\r\n\r\n        # Create a JWT payload\r\n        $payload = [Ordered]@{\r\n            'iss' = \"$($AppId)\"\r\n            'sub' = \"$($AppId)\"\r\n            'aud' = \"https://login.microsoftonline.com/$($TenantId)/oauth2/token\"\r\n            'exp' = ($currentUnixTimestamp + 3600) # Expires in 1 hour\r\n            'nbf' = ($currentUnixTimestamp - 300) # Not before 5 minutes ago\r\n            'iat' = $currentUnixTimestamp\r\n            'jti' = [Guid]::NewGuid().ToString()\r\n        } | ConvertTo-Json\r\n        $base64Payload = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payload)).Replace('+', '-').Replace('/', '_').Replace('=', '')\r\n\r\n        # Extract the private key from the certificate\r\n        $rsaPrivate = $Certificate.PrivateKey\r\n        $rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new()\r\n        $rsa.ImportParameters($rsaPrivate.ExportParameters($true))\r\n\r\n        # Sign the JWT\r\n        $signatureInput = \"$base64Header.$base64Payload\"\r\n        $signature = $rsa.SignData([Text.Encoding]::UTF8.GetBytes($signatureInput), 'SHA256')\r\n        $base64Signature = [System.Convert]::ToBase64String($signature).Replace('+', '-').Replace('/', '_').Replace('=', '')\r\n\r\n        # Create the JWT token\r\n        $jwtToken = \"$($base64Header).$($base64Payload).$($base64Signature)\"\r\n\r\n        $createEntraAccessTokenBody = @{\r\n            grant_type            = 'client_credentials'\r\n            client_id             = $AppId\r\n            client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'\r\n            client_assertion      = $jwtToken\r\n            resource              = 'https://graph.microsoft.com'\r\n        }\r\n\r\n        $createEntraAccessTokenSplatParams = @{\r\n            Uri         = \"https://login.microsoftonline.com/$($TenantId)/oauth2/token\"\r\n            Body        = $createEntraAccessTokenBody\r\n            Method      = 'POST'\r\n            ContentType = 'application/x-www-form-urlencoded'\r\n            Verbose     = $false\r\n            ErrorAction = 'Stop'\r\n        }\r\n\r\n        $createEntraAccessTokenResponse = Invoke-RestMethod @createEntraAccessTokenSplatParams\r\n        Write-Output $createEntraAccessTokenResponse.access_token\r\n    }\r\n    catch {\r\n        $PSCmdlet.ThrowTerminatingError($_)\r\n    }\r\n}\r\n\r\nfunction Get-MSEntraCertificate {\r\n    [CmdletBinding()]\r\n    param(\r\n        [Parameter(Mandatory)]\r\n        [ValidateNotNullOrEmpty()]\r\n        [string]\r\n        $CertificateBase64String,\r\n        \r\n        [Parameter(Mandatory)]\r\n        [ValidateNotNullOrEmpty()]\r\n        [string]\r\n        $CertificatePassword\r\n    )\r\n    try {\r\n        $rawCertificate = [system.convert]::FromBase64String($CertificateBase64String)\r\n        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawCertificate, $CertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)\r\n        Write-Output $certificate\r\n    }\r\n    catch {\r\n        $PSCmdlet.ThrowTerminatingError($_)\r\n    }\r\n}\r\n#endregion functions\r\n\r\ntry {\r\n    # Convert base64 certificate string to certificate object\r\n    $actionMessage = \"converting base64 certificate string to certificate object\"\r\n    $certificate = Get-MSEntraCertificate -CertificateBase64String $EntraIdCertificateBase64String -CertificatePassword $EntraIdCertificatePassword\r\n    Write-Verbose \"Converted base64 certificate string to certificate object\"\r\n\r\n    # Create access token\r\n    $actionMessage = \"creating access token\"\r\n    $entraToken = Get-MSEntraAccessToken -Certificate $certificate -AppId $EntraIdAppId -TenantId $EntraIdTenantId\r\n    Write-Verbose \"Created access token\"\r\n\r\n    # Create headers\r\n    $actionMessage = \"creating headers\"\r\n    $headers = @{\r\n        \"Authorization\"    = \"Bearer $($entraToken)\"\r\n        \"Accept\"           = \"application/json\"\r\n        \"Content-Type\"     = \"application/json\"\r\n        \"ConsistencyLevel\" = \"eventual\" # Needed to filter on specific attributes (https://docs.microsoft.com/en-us/graph/aad-advanced-queries)\r\n    }\r\n    Write-Verbose \"Created headers\"\r\n\r\n    foreach ($userToAdd in $usersToAdd) {\r\n        try {\r\n            # Add member to group\r\n            # API docs: https://learn.microsoft.com/en-us/graph/api/group-post-members?view=graph-rest-1.0&tabs=http\r\n            $actionMessage = \"adding user [$($userToAdd.displayName)] with id [$($userToAdd.id)] as member to group [$($group.displayName)] with id [$($group.id)]\"\r\n            $addGroupMemberBody = @{ \r\n                \"@odata.id\" = \"https://graph.microsoft.com/v1.0/users/$($userToAdd.id)\"\r\n            }\r\n            $addGroupMemberSplatParams = @{\r\n                Uri         = \"https://graph.microsoft.com/v1.0/groups/$($group.id)/members/`$ref\"\r\n                Headers     = $headers\r\n                Method      = \"POST\"\r\n                Body        = ($addGroupMemberBody | ConvertTo-Json -Depth 10)\r\n                Verbose     = $false\r\n                ErrorAction = \"Stop\"\r\n            }\r\n            $addGroupMemberResponse = Invoke-RestMethod @addGroupMemberSplatParams\r\n            Write-Verbose \"Added user [$($userToAdd.displayName)] with id [$($userToAdd.id)] as member to group [$($group.displayName)] with id [$($group.id)].\"\r\n    \r\n            $Log = @{\r\n                Action            = \"GrantMembership\" # optional. ENUM (undefined = default) \r\n                System            = \"EntraID\" # optional (free format text) \r\n                Message           = \"Added user [$($userToAdd.displayName)] with id [$($userToAdd.id)] as member to group [$($group.displayName)] with id [$($group.id)].\" # required (free format text) \r\n                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                TargetDisplayName = $group.displayName # optional (free format text)\r\n                TargetIdentifier  = $group.id # optional (free format text)\r\n            }\r\n            Write-Information -Tags \"Audit\" -MessageData $log\r\n        }\r\n        catch {\r\n            $ex = $PSItem\r\n            if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or\r\n                $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {\r\n                $errorObj = Resolve-MicrosoftGraphAPIError -ErrorObject $ex\r\n                $auditMessage = \"Error $($actionMessage). Error: $($errorObj.FriendlyMessage)\"\r\n                $warningMessage = \"Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)\"\r\n            }\r\n            else {\r\n                $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\r\n                $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"\r\n            }\r\n\r\n            if ($auditMessage -like \"*One or more added object references already exist for the following modified properties: 'members'*\") {\r\n                $Log = @{\r\n                    Action            = \"GrantMembership\" # optional. ENUM (undefined = default) \r\n                    System            = \"EntraID\" # optional (free format text) \r\n                    Message           = \"Skipped $($actionMessage). Reason: User is already member of this group.\" # required (free format text) \r\n                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                    TargetDisplayName = $group.displayName # optional (free format text)\r\n                    TargetIdentifier  = $group.id # optional (free format text)\r\n                }\r\n                Write-Information -Tags \"Audit\" -MessageData $log\r\n            }\r\n            else {\r\n                $Log = @{\r\n                    Action            = \"GrantMembership\" # optional. ENUM (undefined = default) \r\n                    System            = \"EntraID\" # optional (free format text) \r\n                    Message           = $auditMessage # required (free format text) \r\n                    IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                    TargetDisplayName = $group.displayName # optional (free format text)\r\n                    TargetIdentifier  = $group.id # optional (free format text)\r\n                }\r\n                Write-Information -Tags \"Audit\" -MessageData $log\r\n                Write-Warning $warningMessage\r\n                Write-Error $auditMessage\r\n            }\r\n        }\r\n    }\r\n\r\n    foreach ($userToRemove in $usersToRemove) {\r\n        try {\r\n            # Remove member from group\r\n            # API docs: https://learn.microsoft.com/en-us/graph/api/group-delete-members?view=graph-rest-1.0&tabs=http\r\n            $actionMessage = \"removing user [$($userToRemove.displayName)] with id [$($userToRemove.id)] as member from group [$($group.displayName)] with id [$($group.id)]\"\r\n            $removeGroupMemberSplatParams = @{\r\n                Uri         = \"https://graph.microsoft.com/v1.0/groups/$($group.id)/members/$($userToRemove.id)/`$ref\"\r\n                Headers     = $headers\r\n                Method      = \"DELETE\"\r\n                Verbose     = $false\r\n                ErrorAction = \"Stop\"\r\n            }\r\n    \r\n            $removeGroupMemberResponse = Invoke-RestMethod @removeGroupMemberSplatParams\r\n            Write-Verbose \"Removed user [$($userToRemove.displayName)] with id [$($userToRemove.id)] as member from group [$($group.displayName)] with id [$($group.id)].\"\r\n\r\n            $Log = @{\r\n                Action            = \"RevokeMembership\" # optional. ENUM (undefined = default) \r\n                System            = \"EntraID\" # optional (free format text) \r\n                Message           = \"Removed user [$($userToRemove.displayName)] with id [$($userToRemove.id)] as member from group [$($group.displayName)] with id [$($group.id)].\" # required (free format text) \r\n                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                TargetDisplayName = $group.displayName # optional (free format text)\r\n                TargetIdentifier  = $group.id # optional (free format text)\r\n            }\r\n            Write-Information -Tags \"Audit\" -MessageData $log\r\n        }\r\n        catch {\r\n            $ex = $PSItem\r\n            if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or\r\n                $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {\r\n                $errorObj = Resolve-MicrosoftGraphAPIError -ErrorObject $ex\r\n                $auditMessage = \"Error $($actionMessage). Error: $($errorObj.FriendlyMessage)\"\r\n                $warningMessage = \"Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)\"\r\n            }\r\n            else {\r\n                $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\r\n                $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"\r\n            }\r\n\r\n            if ($auditMessage -like \"*ResourceNotFound*\" -and $auditMessage -like \"*$($group.id)*\") {\r\n                $Log = @{\r\n                    Action            = \"RevokeMembership\" # optional. ENUM (undefined = default) \r\n                    System            = \"EntraID\" # optional (free format text) \r\n                    Message           = \"Skipped $($actionMessage). Reason: User is already no longer member or this group no longer exists.\" # required (free format text) \r\n                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                    TargetDisplayName = $group.displayName # optional (free format text)\r\n                    TargetIdentifier  = $group.id # optional (free format text)\r\n                }\r\n                Write-Information -Tags \"Audit\" -MessageData $log\r\n            }\r\n            else {\r\n                $Log = @{\r\n                    Action            = \"RevokeMembership\" # optional. ENUM (undefined = default) \r\n                    System            = \"EntraID\" # optional (free format text) \r\n                    Message           = $auditMessage # required (free format text) \r\n                    IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                    TargetDisplayName = $group.displayName # optional (free format text)\r\n                    TargetIdentifier  = $group.id # optional (free format text)\r\n                }\r\n                Write-Information -Tags \"Audit\" -MessageData $log\r\n                Write-Warning $warningMessage\r\n                Write-Error $auditMessage\r\n            }\r\n        }\r\n    }\r\n}\r\ncatch {\r\n    $ex = $PSItem\r\n    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or\r\n        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {\r\n        $errorObj = Resolve-MicrosoftGraphAPIError -ErrorObject $ex\r\n        $auditMessage = \"Error $($actionMessage). Error: $($errorObj.FriendlyMessage)\"\r\n        $warningMessage = \"Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)\"\r\n    }\r\n    else {\r\n        $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\r\n        $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"\r\n    }\r\n    $Log = @{\r\n        Action            = \"undefined\" # optional. ENUM (undefined = default) \r\n        System            = \"EntraID\" # optional (free format text) \r\n        Message           = $auditMessage # required (free format text) \r\n        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = $group.displayName # optional (free format text)\r\n        TargetIdentifier  = $group.id # optional (free format text)\r\n    }\r\n    Write-Information -Tags \"Audit\" -MessageData $log\r\n    Write-Warning $warningMessage\r\n    Write-Error $auditMessage\r\n}","runInCloud":true}
'@ 

Invoke-HelloIDDelegatedForm -DelegatedFormName $delegatedFormName -DynamicFormGuid $dynamicFormGuid -AccessGroups $delegatedFormAccessGroupGuids -Categories $delegatedFormCategoryGuids -UseFaIcon "True" -FaIcon "fa fa-users" -task $tmpTask -returnObject ([Ref]$delegatedFormRef) 
<# End: Delegated Form #>

