# HelloID-Conn-SA-Full-Microsoft-Entra-ID-GroupManageMemberships
| This repository contains the connector and configuration code only. The implementer is responsible for acquiring the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

## Description
_HelloID-Conn-SA-Full-Microsoft-Entra-ID-GroupManageMemberships_ is a delegated form template designed for use with HelloID Service Automation (SA) Delegated Forms. It can be imported into HelloID and customized according to your requirements.

By using this delegated form, you can manage group memberships in Microsoft Entra ID (formerly Azure AD). The following options are available:
 1. Search and select an Entra ID group (wildcard search by display name, description, or mail)
 2. View current group members
 3. Select users to add to or remove from the group
 4. Group memberships are updated in Microsoft Entra ID

## Getting started

### Requirements

#### App Registration & Certificate Setup

Before implementing this connector, make sure to configure a Microsoft Entra ID, an App Registration. During the setup process, you’ll create a new App Registration in the Entra portal, assign the necessary API permissions (such as user and group read/write), and generate and assign a certificate.

Follow the official Microsoft documentation for creating an App Registration and setting up certificate-based authentication:
- [App-only authentication with certificate (Exchange Online)](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps#set-up-app-only-authentication)

#### HelloID-specific configuration

Once you have completed the Microsoft setup and followed their best practices, configure the following HelloID-specific requirements.

- **API Permissions** (Application permissions):
  - `User.ReadWrite.All`
  - `Group.ReadWrite.All`
  - `GroupMember.ReadWrite.All`
  - `UserAuthenticationMethod.ReadWrite.All`
  - `User.EnableDisableAccount.All`
  - `User-PasswordProfile.ReadWrite.All`
  - `User-Phone.ReadWrite.All`
- **Certificate:**
  - Upload the public key file (.cer) in Entra ID
  - Provide the certificate as a Base64 string in HelloID. For instructions on creating the certificate and obtaining the base64 string, refer to our forum post: [Setting up a certificate for Microsoft Graph API in HelloID connectors](https://forum.helloid.com/forum/helloid-provisioning/5338-instruction-setting-up-a-certificate-for-microsoft-graph-api-in-helloid-connectors#post5338)


#### HelloID-specific configuration

Once you have completed the Microsoft setup and followed their best practices, configure the following HelloID-specific requirements.

- **API Permissions (Application permissions)**:
  - `Group.Read.All` - To read group information
  - `GroupMember.ReadWrite.All` - To manage group memberships
  - `User.Read.All` - To read user information

- **Certificate Base64 encoded string**:
  - Base64 encoded string of the certificate assigned to the app registration. For instructions on creating the certificate and obtaining the base64 string, refer to our forum post: [Setting up a certificate for Microsoft Graph API in HelloID connectors](https://forum.helloid.com/forum/helloid-provisioning/5338-instruction-setting-up-a-certificate-for-microsoft-graph-api-in-helloid-connectors#post5338)

### Connection settings

The following user-defined variables are used by the connector.

| Setting                        | Description                                                              | Mandatory |
| ------------------------------ | ------------------------------------------------------------------------ | --------- |
| EntraIdTenantId                | The unique identifier (ID) of the tenant in Microsoft Entra ID           | Yes       |
| EntraIdAppId                   | The unique identifier (ID) of the App Registration in Microsoft Entra ID | Yes       |
| EntraIdCertificateBase64String | The Base64-encoded string representation of the app certificate          | Yes       |
| EntraIdCertificatePassword     | The password associated with the app certificate                         | Yes       |

## Remarks

### Group Filtering
- **Supported Group Types**: The connector filters groups to include Microsoft 365 groups (Unified) and cloud-only security groups. It excludes:
  - Dynamic membership groups
  - On-premises synchronized groups
  - Mail-enabled groups (excluding Microsoft 365 groups)
  - Microsoft Teams-provisioned groups

### Wildcard Search
- **Search Functionality**: Users can search for groups using a wildcard (`*`) to return all groups, or by entering partial text to search across display name, description, and mail fields. This provides flexible group discovery based on multiple attributes.

### Certificate-Based Authentication
- **JWT Token Generation**: The connector uses certificate-based authentication to generate JSON Web Tokens (JWT) for secure communication with Microsoft Graph API. The certificate is converted from a base64 string and used to sign the JWT assertion for OAuth2 authentication.

### Error Handling
- **Duplicate Member Addition**: If attempting to add a user who is already a member of the group, the operation is skipped with an appropriate audit log entry rather than failing.
- **Member Removal**: If attempting to remove a user who is not a member or if the group no longer exists, the operation is skipped with an informational audit log entry.

## Development resources

### API endpoints

The following Microsoft Graph API endpoints are used by the connector:

| Endpoint                                | Description        |
| --------------------------------------- | ------------------ |
| /v1.0/users                             | List users         |
| /v1.0/groups                            | List groups        |
| /v1.0/groups/{id}/members               | List group members |
| /v1.0/groups/{id}/members/$ref          | Add member         |
| /v1.0/groups/{id}/members/{userId}/$ref | Remove member      |

### API documentation

- [List users](https://learn.microsoft.com/en-us/graph/api/user-list)
- [List groups](https://learn.microsoft.com/en-us/graph/api/group-list)
- [List group members](https://learn.microsoft.com/en-us/graph/api/group-list-members)
- [Add group member](https://learn.microsoft.com/en-us/graph/api/group-post-members)
- [Remove group member](https://learn.microsoft.com/en-us/graph/api/group-delete-members)


## Getting help

> :bulb: **Tip:**  
> For more information on Delegated Forms, please refer to our documentation pages: https://docs.helloid.com/en/service-automation/delegated-forms.html


## HelloID docs
The official HelloID documentation can be found at: https://docs.helloid.com/