Dispak
======

Simple code and server/services management tool.

Dispak is a very easy-to-use command-line tool. Its primary goal is to manage versions of any software projet (which source code is managed using [git](https://en.wikipedia.org/wiki/Git)), by helping to list existing tags, create new tags and install tags on servers.

Furthermore, it is very easy to add custom rules; then Dispak becomes a central tool that centralizes all the scripts needed by your projects.

It is written in pure shell, so it can be used on any Unix/Linux machine.

Dispak was created by [Amaury Bouchard](http://amaury.net) and is [open-source software](#what-is-arkivs-license).


************************************************************************

Table of contents
-----------------

1. [Main features](#1-main-features)
   1. [Basics](#11-basics)
   2. [Help](#12-help)
   3. [List tags](#13-list-tags)
   4. [Create tag](#14-create-tag)
   5. [Install tag](#15-install-tag)
2. [Installation](#2-installation)
   1. [Prerequisites](#21-prerequisites)
   2. [Source installation](#22-source-installation)
   3. [Configuration](#23-configuration)
3. [Create your own rules](#3-create-your-own-rules)


************************************************************************

## 1. Main features

### 1.1 Basics

Dispak manage three kinds of [deployment environments](https://en.wikipedia.org/wiki/Deployment_environment):
- `dev`: Development environment, like developers' workstations.
- `test`: Testing/staging environment, used to validate a version.
- `prod`: Production environment, where the live service is accessed by users.

Dispak is based on [semantic versioning](https://semver.org/) and [odd numbered versions for unstable releases](https://en.wikipedia.org/wiki/Software_versioning#Odd-numbered_versions_for_development_releases), which are common for software projects.

All tags are named in the form `X.Y.Z`:
- `X`: Major version number. Should be incremented in case of major feature evolution or backward compatibility break.
- `Y`: Minor version number. Should be incremented for every minor feature evolution.
   - Even numbers (0, 2, 4, ...) are used for 'stable' versions.
   - Odd numbers (1, 3, 5, ...) are used for 'unstable' versions.
- `Z`: Revision number. Should be incremented for bug fixes.

Only stable versions can be installed on production servers.

### 1.2 Help

To see the list of rules offered by Dispak (general and project-specific rules), you just have to type:
```shell
$ dpk help
```

### 1.3 List tags

To see the list of existing tags already created for the current project:
```shell
$ dpk tags
```

This command displays a condensed list (intermediate revisions are not shown).

To see all revisions, with their detailed annotation messages:
```shell
$ dpk tags --all
```

### 1.4 Create tag

You can easily create a new tagged version:
```shell
$ dpk pkg
```

Dispak will check several things, depending of the configuration (see below). Dispak will ask you which version number you want to use (new revision, new stable minor, new unstable minor, new major); otherwise you can give the desired version number directly:
```shell
$ dpk pkg --tag=3.2.0
```

### 1.5 Install tag

To install the last created tag:
```shell
$ dpk install
```

Dispak will detect which tag to use, and what kind of platform (`dev`, `test` or `prod`) is corresponding to the local machine.

Alternatively, you can specify the tag and/or the local platform:
```shell
$ dpk install --platform=test --tag=3.2.1
```


************************************************************************

## 2. Installation

### 2.1 Prerequisites

### 2.2 Source installation

### 2.3 Configuration


************************************************************************

## 3. Create your own rules

