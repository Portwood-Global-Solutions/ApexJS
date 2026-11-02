# Install ApexJS

ApexJS is distributed as a first-generation **unmanaged** Salesforce package. You can install it through Salesforce without cloning the repository, using Salesforce CLI, or building JavaScript locally.

## Installation links

| Destination                     | Salesforce installer                                                                                                                   |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Sandbox                         | [Install ApexJS in a sandbox](https://test.salesforce.com/packaging/installPackage.apexp?p0=04tVx000001C6nRIAS)                        |
| Production or Developer Edition | [Install ApexJS in production or Developer Edition](https://login.salesforce.com/packaging/installPackage.apexp?p0=04tVx000001C6nRIAS) |

Package version ID: `04tVx000001C6nRIAS`. The permanent package host is **Portwood Global - Production**. These are Salesforce installation links for the unmanaged package.

The Salesforce installer is version **1.1**, named **ApexJS 0.1.0**, and contains source release **0.1.0**. The package has no namespace, no installation password, and no Portwood package dependency. ApexJS is licensed under the [MIT License](../LICENSE).

## Install and enable the actions

1. Open the sandbox installation link first. For a Developer Edition or production org, use the production/developer link and log in to the intended org. Confirm the org and package name on Salesforce's installation screen.
2. Select **Install for Admins Only**, then click **Install**. Wait for Salesforce to report that installation is complete. If Salesforce asks to notify you when it finishes, check Setup → Installed Packages afterward.
3. In Setup → Permission Sets, open **ApexJS Author**. Use **Manage Assignments** to assign it to the people who design the Flows. They also need the usual Salesforce permissions to manage Flows; this permission set does not grant them.
4. Assign **ApexJS User** to users whose Flow execution context needs the runtime classes. Authors already have runtime class access through ApexJS Author.
5. Reload Flow Builder, add an Action, and search for **ApexJS**. Confirm that **Run JavaScript on Collections**, **Read JavaScript Result**, and **Prepare Portwood Data** are available.
6. Follow the [first Flow walkthrough](admin-guide.md#first-flow-sum-opportunity-amounts). Check the action's success/error outputs and connect its fault path before activation.
7. To use a library, upload compatible source as a Static Resource and configure it in the action's library section. See the [library guide](libraries.md). The example `ApexJSExampleTools` resource is included.

Use an org that supports Apex and Metadata API 68.0, including the structured Flow inputs used by this release. Portwood is needed only if you want to generate a Portwood document after preparing data.

## What is installed

| Metadata                        | Count | Purpose                                                                         |
| ------------------------------- | ----- | ------------------------------------------------------------------------------- |
| Apex classes                    | 54    | Interpreter, three actions, input/output types, library support, and Apex tests |
| Lightning Web Component bundles | 6     | Flow property editors and their helpers                                         |
| Permission sets                 | 2     | ApexJS Author and ApexJS User                                                   |
| Static Resources                | 1     | ApexJSExampleTools example module                                               |

The package adds no custom objects, triggers, active Flows, scheduled jobs, or customer records. Example Flows remain optional source files in the repository and are not installed automatically.

## Existing source deployments and updates

The package uses the same component names as the source distribution. If an org already contains ApexJS or earlier research components with those names, review the existing metadata and your changes before trying the installer. A fresh sandbox or scratch org provides the clearest installation test.

Unmanaged components are editable after installation and do not support managed-package upgrades. Plan later changes as reviewed metadata deployments, preserving local modifications. Do not uninstall an existing copy simply to update it; first inspect any Flows and other dependencies that use its classes or editors. See Salesforce's [unmanaged package guidance](https://developer.salesforce.com/docs/platform/pkg1-dev/guide/packaging-developing-unmanaged.html).

## Alternative: deploy the source or ZIP

The [README](../README.md#install-from-source) provides source deployment commands. The GitHub release also includes a Metadata API ZIP and its SHA-256 checksum for deployment tooling. A ZIP download by itself does not install anything; use the Salesforce installation link for the guided installer.

Administrators with deployment tooling can deploy the archive with:

```sh
sf project deploy start --metadata-dir ApexJS-0.1.0-unmanaged.zip --single-package --target-org YOUR_ORG --test-level RunLocalTests --wait 30
```

Follow the same permission-set assignment and Flow validation steps afterward. See the [verification results](verification.md) for the checks completed on the installed package.
