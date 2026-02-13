# Welcome to IaC Hub

Infrastructure as Code (IaC) is revolutionizing how we deploy and manage cloud infrastructure. This site is your comprehensive guide to mastering **Azure Bicep** and **Terraform**.

## What You'll Learn

### :material-microsoft-azure: Azure Bicep

Learn Azure's native Infrastructure as Code language with domain-specific syntax designed for Azure deployments.

[:octicons-arrow-right-24: Get started with Bicep](bicep/getting-started.md)

### :material-terraform: Terraform

Master HashiCorp's multi-cloud IaC tool with HCL syntax for managing infrastructure across any cloud provider.

[:octicons-arrow-right-24: Get started with Terraform](terraform/getting-started.md)

## Why Infrastructure as Code?

!!! tip "Benefits of IaC"

    - **Consistency**: Deploy identical environments every time
    - **Version Control**: Track infrastructure changes like code
    - **Automation**: Reduce manual errors and deployment time
    - **Documentation**: Your code IS your documentation
    - **Collaboration**: Teams can review and collaborate on infrastructure

## Quick Comparison

| Feature | Bicep | Terraform |
|---------|-------|-----------|
| **Provider** | Microsoft | HashiCorp |
| **Cloud Support** | Azure only | Multi-cloud |
| **Language** | Bicep DSL | HCL |
| **State Management** | Azure-managed | Local/Remote |
| **Learning Curve** | Moderate | Moderate-High |

## Getting Started

Choose your path based on your needs:

=== "Azure Only"

    If you're working exclusively with Azure, **Bicep** is the recommended choice:
    
    ```bash
    # Install Azure CLI with Bicep
    az bicep install
    
    # Verify installation
    az bicep version
    ```

=== "Multi-Cloud"

    For multi-cloud or hybrid environments, **Terraform** is your best option:
    
    ```bash
    # Install Terraform (Windows)
    winget install HashiCorp.Terraform
    
    # Verify installation
    terraform version
    ```

## Featured Articles

- [Bicep Best Practices](bicep/best-practices.md) - Write clean, maintainable Bicep code
- [Terraform Modules](terraform/modules.md) - Create reusable Terraform modules
- [Bicep vs Terraform](comparisons/bicep-vs-terraform.md) - Detailed comparison

## About This Site

This site is maintained by [Rushikesh Deshmukh](https://github.com/rushideshmukh-tech). Feel free to contribute or report issues on [GitHub](https://github.com/rushideshmukh-tech/rushideshmukh-tech).

---

!!! info "Stay Updated"

    This site is regularly updated with new content, examples, and best practices. Star the repository to get notified of updates!
