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
3. [How it works](#3how-it-works)
   1. [Database migrations](#31-database-migrations)
   2. [Crontab installation](#32-crontab-installation)
   3. [Pre/post scripts execution](#33-pre-post-scripts-execution)
   4. [Files generation](#34-files-generation)
   5. [Static files, symlinks and Amazon S3](#35-static-files-symlinks-and-amazon-s3)
   6. [Apache configuration](#36-apache-configuration)
   7. [Configuration file](#37-configuration-file)
4. [Create your own rules](#4-create-your-own-rules)
   1. [Why should you create your own rules?](#41-why-should-you-create-your-own-rules)
   2. [Where to put the rule?](#42-where-to-put-the-rule)
   3. [Simple example](#43-simple-example)
   4. [Advanced example](#44-advanced-example)
   5. [Provided functions](#45-provided-functions)


************************************************************************

## 1. Main features

### 1.1 Basics

#### 1.1.1 Platform environments
Dispak manage three kinds of [deployment environments](https://en.wikipedia.org/wiki/Deployment_environment):
- `dev`: Development environment, like developers' workstations.
- `test`: Testing/staging environment, used to validate a version.
- `prod`: Production environment, where the live service is accessed by users.

Sometimes, Dispak can guess the platform on which it is executed (see [Install tag](#15-install-tag)), using the local machine's name.
- If the hostname starts with `test` followed by numbers, it assumes to be on a `test` platform.
- If the hostname starts with `prod`, `web`, `db`, `cron`, `worker`, `front` or `back`, followed by numbers, it assumes to be on a `prod` platform.
- Otherwise it assumes to be on a `dev` platform.

#### 1.1.2 Version numbering
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
$ dpk

or

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

This command also tells the number of commits since the last tag.


### 1.4 Create tag

You can easily create a new tagged version:
```shell
$ dpk pkg
```

Dispak will ask you which version number you want to use (new revision, new stable minor, new unstable minor, new major); otherwise you can give the desired version number directly:
```shell
$ dpk pkg --tag=3.2.0
```
In any case, it is *not possible* to "jump" version numbers (for example, going from 1.2.0 to 1.2.5, or from 2.0.0 to 2.3.0).

Dispak will check several things and perform some operations, depending of the configuration (see below):
- Check if you are on the `master` branch.
- Check for uncommitted and unpushed files.
- Execute pre-packaging scripts.
- Commit the database migration file.
- Minify JS/CSS files.
- **Create the tag.**
- Send static files to Amazon S3.
- Unminify files (delete minified files if they are not version controlled).
- Execute post-packaging files.


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

Dispak will perform these operations:
- Ensure that no unstable tag is installed on a production server.
- Remove previously created symlink (see below).
- Execute pre-install scripts.
- Deploy new version's source code.
- Install crontab file.
- Perform database migration.
- 


************************************************************************

## 2. Installation

### 2.1 Prerequisites

#### 2.1.1 Basic
These tools are nedded by Dispak to work correctly. They are usually installed by default on every Unix/Linux distributions.
- A not-so-old [`bash`](https://en.wikipedia.org/wiki/Bash_(Unix_shell)) Shell interpreter located on `/bin/bash` (mandatory)
- [`git`](https://en.wikipedia.org/wiki/Git) (mandatory)
- [`tput`](https://en.wikipedia.org/wiki/Tput) for [ANSI text formatting](https://en.wikipedia.org/wiki/ANSI_escape_code) (optional: automatically deactivated if not installed)

#### 2.1.2 Minifier
If you want to use Dispak for Javascript and/or CSS files minification, you need to install [`NodeJS`](https://en.wikipedia.org/wiki/Node.js) with the [`minifier` package](https://www.npmjs.com/package/minifier).

To install these tools on Ubuntu:
```shell
# apt-get install nodejs
# npm install -g minifier
```

#### 2.1.3 Amazon Web Services
If you want to upload static files on [Amazon S3](https://aws.amazon.com/s3/), you have to follow these steps:
- Create a dedicated bucket.
- Create an [IAM](https://aws.amazon.com/iam/) user with read-write access to this bucket.
- Install the [AWS-CLI](https://aws.amazon.com/cli/) program and [configure it](http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html).

Install AWS-CLI on Ubuntu:
```shell
# apt-get install awscli
```

Configure the program (you will be asked for the AWS user's access key and secret key, and the used datacenter):
```shell
# aws configure
```


### 2.2 Source installation

Get the last version:
```shell
$ wget https://github.com/Amaury/Dispak/archive/0.1.0.zip
$ unzip Dispak-0.9.1.zip

or

$ wget https://github.com/Amaury/Dispak/archive/0.1.0.tar.gz
$ tar xzf Dispak-0.9.1.tar.gz
```

You can also clone the git source code repository:
```shell
$ git clone https://github.com/Amaury/Dispak
```

Then you can add an alias in your `~/.bashrc` or `~/.bash_aliases` file:
```shell
alias dpk='/path/to/Dispak/dpk'
```

This alias is very useful, it allows you to simply type `dpk` from anywhere in a git repository tree.


************************************************************************

## 3. How it works

### 3.1 Database migrations

Dispak can manage the evolution of your database model.

First of all, you must create a table in all your database servers (testing, staging and production). This table will be used to keep track of which evolutions have been processed on the server.

Definition of the table:
```sql
CREATE TABLE DatabaseMigration (
	dbm_i_id	INT UNSIGNED NOT NULL AUTO_INCREMENT,
	dbm_d_creation	DATETIME NOT NULL,
	dbm_t_update	TIMESTAMP NOT NULL,
	dbm_d_done	DATETIME DEFAULT NULL,
	dbm_s_version	TINYTEXT NOT NULL,
	PRIMARY KEY (dbm_i_id),
	INDEX dbm_d_creation (dbm_d_creation),
	INDEX dbm_t_update (dbm_t_update),
	INDEX dbm_d_done (dbm_d_done),
	INDEX dbm_d_version (dbm_s_version(10))
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
```

The rest of the process is fairly simple:
1. In your Dispak configuration file (see [below](#35-configuration-file)), fill the database related variables (`CONF_DB_HOST`, `CONF_DB_USER`, `CONF_DB_PWD`, `CONF_DB_MIGRATION_BASE`, `CONF_DB_MIGRATION_TABLE`).
2. In your project's repository, create a `etc/database/migrations` directory.
3. In this directory, you must create a file named `current` which will contain all your `ALTER` commands. You must commit this file.
4. When you create a new tag with `dpk pkg`, the `current` file will be renamed with the tag version number(`X.Y.Z`), and a new empty `current` file is created.
5. When you deploy a tag on a server (`dpk install` command), Dispak will check in the migration table which was the last migration executed; then it will process every migration files that are not already processed, in their creation order.


### 3.2 Crontab installation

### 3.3 Pre/post scripts execution

### 3.4 Files generation

### 3.5 Static files, symlinks and Amazon S3

### 3.6 Apache configuration

### 3.7 Configuration file

In a git repository, you can create a `dispak.conf` or `etc/dispak.conf` file. Look at the [`dispak-example.conf`](https://github.com/Amaury/Dispak/blob/master/dispak-example.conf) example file in the Dispak source repository.

There is three kind of configuration variables:
- Single values. The variable is waiting for a single value or file path.
- List of values. The variable is waiting for a single shell string (the whole content is surrounded by quotes) which can contain many values, separated with space or carriage return characters.
- Associative arrays. The variable may have many keys, each one could be affected to a single value or to a list of values.

Here are the definable variables:
- **Main configuration**
  - `CONF_PLATFORM`: IF you don't want Dispak to detect the platform, you can set what is the current environment (`dev`, `test` or `prod`).
  - `CONF_DEFAULT_SECTION`: Rules (actions the Dispak can execute) are listed using the `dpk help` command. They are grouped by section. Every rules that don't define a specific section are grouped in a `Default` one, and this name can be overridden using the `CONF_DEFAULT_SECTION` variable.
- **pkg rule**
  - `CONF_PKG_CHECK_URL`: You can ask Dispak to check the return status of the given URL before creating a new tag. This is convenient if you have a local page that show the result of your unit tests; if the HTTP status of this page is an error (not equal to 200), the tag is not created.
  - `CONF_PKG_SCRIPTS_PRE`: You can ask Dispak to execute a list of scripts before creating a new tag.
  - `CONF_PKG_SCRIPTS_POST`: You can ask Dispak to execute a list of scripts after creating a new tag. These scripts are not executed if there was an error during the process.
  - `CONF_PKG_MINIFY`: It is possible to concatenate many files into one Javacript or CSS file, and then to minify this file. The `CONF_PKG_MINIFY` variable is an associative array. For each entry, the key is the path to the generated file, and the value is the list of source files.
  - `CONF_PKG_S3`: If you want to copy static files to Amazon S3, use this variable. It is an associative array; for each entry, the key is the S3 bucket where the files will be copied, and the value is the path to the file or the directory that will be recursively copied. The files are copied in a sub-directory of the bucket's root, which name is the tag's version number.
- **install rule**
  - `CONF_INSTALL_SYMLINK`: Use this variable if you need to create symlinks when you install a new version. It is an associative array; the key is the path to the link's directory; the value is the path pointed by the link. The link will be created in its destination directory, and its name is the installed tag's version number.
  - `CONF_INSTALL_SCRIPTS_PRE`: Here is a list of scripts to execute before install.
  - `CONF_INSTALL_SCRIPTS_POST`: Here is a list of scripts to execute after install. The scripts are not executed if an error has occured during the install process.
  - `CONF_INSTALL_APACHE_FILES`: This variable must contain a list of Apache configuration files. These files are listed in the system configuration (in `/etc/apache2/sites-available` and linked in `/etc/apache2/sites-enabled`) if they are not already.
  - `CONF_INSTALL_CHOWN`: Associative array. The keys are user logins, and the values are path to files and/or directories that must be changed of owner.
  - `CONF_INSTALL_CHMOD`: Associative array. The keys are a `chmod` file right (like `+x` or `644`), and the values are lists of files and/or directories that must be `chmod`'ed.
  - `CONF_INSTALL_GENERATE`: The variable must contain a list of files that must be *generated* after install. Each entry of the list must be the path to the *generated* file. For each one of them, a *generator* script must exist with the same name and a `.gen` extension. When a generator script is executed, everything coming out from its STDOUT will be written in the generated file. For their execution, the generator scripts receive two parameters; the first one is the platform environment type (`dev`, `test` or `prod`); the second one is the installed tag version number.
- **Database management**
  - `CONF_DB_HOST`: Database host name.
  - `CONF_DB_USER`: Database connection user name.
  - `CONF_DB_PWD`: Database connection password.
  - `CONF_DB_MIGRATION_BASE`: Name of the base which contains the migration table.
  - `CONF_DB_MIGRATION_TABLE`: Name of the table which contains migration information.

************************************************************************

## 4. Create your own rules

### 4.1 Why should you create your own rules?

### 4.2 Where to put the rule?

### 4.3 Simple example

### 4.4 Advanced example

### 4.5 Provided functions

**`check_aws`**
Check if the `aws-cli` program is installed. Abort if not.

**`check_dhbost`**
Check if the database host is defined and reachable (using `ping`). Abort if not.

**`check_sudo`**
Check if the user has sudo rights. Abort if not.

**`check_git`**
Check if we are in a git repository. Abort if not.

**`check_platform`**
Check the platform given as parameter, or detect the platform.
The current platform is set in the `$DPK_OPTIONS["platform"]` variable.

**`check_tag`**
Check if the tag given as a parameter already exists. Abort if not.
If no tag is given, fetch the last created tag and put it in the `$DPK_OPTIONS["tag"]` variable.

**`check_next_tag`**
Check if the tag given as a parameter is valid as the next tag. If not or if no tag is given, a list of valid tags is shown to the user, who must choose between them.
Then the tag is available in the `$DPK_OPTIONS["tag"]` variable.

