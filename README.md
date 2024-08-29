Dispak
======

Simple code and server/services management tool.

Dispak is a very easy-to-use command-line tool. Its primary goal is to manage versions of any software projet (which source code is managed using [git](https://en.wikipedia.org/wiki/Git)), by helping to list existing tags, create new tags and install tags on servers. It handles MySQL [database migrations](https://en.wikipedia.org/wiki/Schema_migration), JS/CSS files concatenation and minification, [crontab](https://en.wikipedia.org/wiki/Cron) installation, [Apache](https://en.wikipedia.org/wiki/Apache_HTTP_Server) configuration files installation, static files versioned access (locally or copied on [Amazon S3](https://aws.amazon.com/s3/)).

Furthermore, it is very easy to add custom rules; then Dispak becomes a central tool that brings together all the scripts needed by your projects.

It is written in pure shell, so it can be used on any Unix/Linux machine.

Dispak was created by [Amaury Bouchard](http://amaury.net) and is [open-source software](https://en.wikipedia.org/wiki/MIT_License).


************************************************************************

Table of contents
-----------------

1. [Main features](#1-main-features)
   1. [Basics](#11-basics)
   2. [Help](#12-help)
   3. [List tags](#13-list-tags)
   4. [Create tag](#14-create-tag)
   5. [Install tag](#15-install-tag)
   6. [Refresh configuration](#16-configure)
   7. [Branch management](#17-branch-management)
2. [Installation](#2-installation)
   1. [Prerequisites](#21-prerequisites)
   2. [Source installation](#22-source-installation)
   3. [Post-install](#23-post-install)
3. [How it works](#3how-it-works)
   1. [Database migrations](#31-database-migrations)
   2. [Crontab installation](#32-crontab-installation)
   3. [Pre/post scripts execution](#33-pre-post-scripts-execution)
   4. [Files generation](#34-files-generation)
   5. [Static files, symlinks and Amazon S3](#35-static-files-symlinks-and-amazon-s3)
   6. [Javascript and CSS files concatenation and minification](#36-javascript-and-css-files-concatenation-and-minification)
   7. [Apache configuration](#37-apache-configuration)
   8. [Configuration file](#38-configuration-file)
4. [Create your own rules](#4-create-your-own-rules)
   1. [Why should you create your own rules?](#41-why-should-you-create-your-own-rules)
   2. [Where to put the rule?](#42-where-to-put-the-rule)
   3. [Simple example](#43-simple-example)
   4. [Parameters management](#44-parameters-management)
   5. [Documentation section](#45-documentation-section)
   6. [Configuration](#46-configuration)
   7. [Advanced example](#46-advanced-example)
   8. [Provided variables](#48-provided-variables)
   9. [Provided functions](#49-provided-functions)


************************************************************************

## 1. Main features

### 1.1 Basics

#### 1.1.1 Platform environments
Dispak manage three kinds of [deployment environments](https://en.wikipedia.org/wiki/Deployment_environment):
- `dev`: Development environment, like developers' workstations.
- `test`: Testing/staging environment, used to validate a version.
- `prod`: Production environment, where the live service is accessed by users.

Unless specified otherwise in the configuration file, Dispak can guess the platform on which it is executed (see [Install tag](#15-install-tag)), using the local machine's name.
- If the hostname starts with `test`, `preprod` or `pprod`, followed by numbers, it assumes to be on a `test` platform.
- If the hostname starts with `server`, `serv`, `prod`, `web`, `db`, `cron`, `worker`, `front` or `back`, followed by numbers, it assumes to be on a `prod` platform.
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

![Dispak help](http://www.geek-directeur-technique.com/wp-content/uploads/2018/01/help-1024x511.png)

To see the list of rules offered by Dispak (general and project-specific rules), you just have to type:
```shell
$ dpk

or

$ dpk help
```

You can see the documentation of a single rule:
```shell
$ dpk help tags
$ dpk help install
```


### 1.3 List tags

To see the list of existing tags already created for the current project:
```shell
$ dpk tags
```

![Dispak list tags](http://www.geek-directeur-technique.com/wp-content/uploads/2018/01/tags-300x282.png)

This command displays a condensed list (intermediate revisions are not shown).

To see all revisions, with their detailed annotation messages:
```shell
$ dpk tags --all
```

![Dispak list tags full](http://www.geek-directeur-technique.com/wp-content/uploads/2018/01/tags-all-300x222.png)

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
- Execute pre-packaging scripts (see [below](#33-pre-post-scripts-execution)).
- Commit the database migration file (see [below](#31-database-migrations)).
- Minify JS/CSS files (see [below](#36-javascript-and-css-files-concatenation-and-minification)).
- **Create the tag.**
- Send static files to Amazon S3 (see [below](#35-static-files-symlinks-and-amazon-s3)).
- Unminify files (delete minified files if they are not version controlled).
- Execute post-packaging files (see [below](#33-pre-post-scripts-execution)).


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
- Remove previously created symlink (see [below](#35-static-files-symlinks-and-amazon-s3)).
- Execute pre-install scripts (see [below](#33-pre-post-scripts-execution)).
- Execute pre-configuration scripts (see [below](#33-pre-post-scripts-execution)).
- **Deploy new version's source code.**
- Install crontab file (see [below](#32-crontab-installation)).
- Perform database migration (see [below](#31-database-migrations)).
- Install Apache configuration files (see [below](#37-apache-configuration)).
- Set files ownership (see [configuration](#38-configuration-file)).
- Set files access rights (see [configuration](#38-configuration-file)).
- Generate files (see [below](#34-files-generation)).
- Execute post-configuration scripts (see [below](#33-pre-post-scripts-execution)).
- Execute post-install scripts (see [below](#33-pre-post-scripts-execution)).

Options are available to disable some operations:
- `--no-apache`: Apache configuration files are *not* installed, even if Apache is installed on the current machine.
- `--no-crontab`: Crontab file is not installed.
- `--no-db-migration`: Database migration is not performed.


### 1.6 Refresh configuration

It is possible to re-configure an already deployed tag or branch, by using this command:
```shell
$ dpk config
```

Dispak will detect which tag to use, and what kind of platform (`dev`, `test` or `prod`) is corresponding to the local machine.

Alternatively, you can specify the tag and/or the local platform:
```shell
$ dpk config --platform=test --tag=main
```

Dispak will perform these operations:
- Execute pre-configuration scripts (see [below](#33-pre-post-scripts-execution)).
- Install crontab file (see [below](#32-crontab-installation)).
- Install Apache configuration files (see [below](#37-apache-configuration)).
- Set files ownership (see [configuration](#38-configuration-file)).
- Set files access rights (see [configuration](#38-configuration-file)).
- Generate files (see [below](#34-files-generation)).
- Execute post-configuration scripts (see [below](#33-pre-post-scripts-execution)).

It is a subset of the `dpk install` command, useful to refresh the local configuration of a project after updating its files manually.


### 1.7 Branches management

Dispak helps you to do basic branches management.

#### List
You can list all existing tags:
```shell
$ dpk branch --list
```

#### Create branches
You can create a new branch. Branches are created from the last commit of the `master` branch, or from a given tag if the option `--tag` is used.
```shell
# create a branch from the last commit of the 'master' branch
$ dpk branch --create=name_of_the_branch

# create a branch from a tag
$ dpk branch --create=name_of_the_branch --tag=X.Y.Z
```
Branches are created locally and on the remote git repository.

#### Remove branches
You can delete a previously created branch:
```shell
$ dpk branch --remove=name_of_the_branch
```
Branches are deleted locally and from the remote git repository.

#### Merge
You can merge the current branch on the `master` branch:
```shell
$ dpk branch --merge
```
The merged result is pushed to the remote git repository.

#### Backport
You can merge the `master` branch on the current branch:
```shell
$ dpk branch --backport
```
The merged result is pushed to the remote git repository.


************************************************************************

## 2. Installation

### 2.1 Prerequisites

#### 2.1.1 Basic
These tools are nedded by Dispak to work correctly. They are usually installed by default on every Unix/Linux distributions.
- [`bash`](https://en.wikipedia.org/wiki/Bash_(Unix_shell)) Shell interpreter version >= 4.0, located on `/bin/bash` (mandatory)
- [`git`](https://en.wikipedia.org/wiki/Git) (mandatory)
- [`tput`](https://en.wikipedia.org/wiki/Tput) for [ANSI text formatting](https://en.wikipedia.org/wiki/ANSI_escape_code) (optional: automatically deactivated if not installed)

On Mac OS X, the installed version of `bash` is obsolete. You need to install a recent version using `brew`, and then change the `/bin/bash` symlink:
```shell
# brew install bash
# rm -f /bin/bash
# ln -s /usr/local/bin/bash /bin/bash
```

To install `git` on Ubuntu:
```shell
# apt install git
```

#### 2.1.2 Minifier
If you want to use Dispak for Javascript and/or CSS files minification, you need to install [`NodeJS`](https://en.wikipedia.org/wiki/Node.js) with the [`minifier` package](https://www.npmjs.com/package/minifier).

To install these tools on Ubuntu:
```shell
# apt install nodejs
# npm install -g minifier
```

#### 2.1.3 Amazon Web Services
If you want to upload static files on [Amazon S3](https://aws.amazon.com/s3/), you have to follow these steps:
- Create a dedicated bucket.
- Create an [IAM](https://aws.amazon.com/iam/) user with read-write access to this bucket.
- Install the [AWS-CLI](https://aws.amazon.com/cli/) program and [configure it](http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html).

Install AWS-CLI on Ubuntu:
```shell
# apt install awscli
```

Configure the program (you will be asked for the AWS user's access key and secret key, and the used datacenter):
```shell
# aws configure
```


### 2.2 Source installation

You can install Dispak anywhere on your disk drive. The preferred path (if you have sudo rights) is `/opt/Dispak`, but it can be under your own home.

Get the last version:
```shell
$ wget https://github.com/Amaury/Dispak/archive/0.14.0.zip
$ unzip Dispak-0.14.0.zip

or

$ wget https://github.com/Amaury/Dispak/archive/0.14.0.tar.gz
$ tar xzf Dispak-0.14.0.tar.gz
```

You can also clone the git source code repository:
```shell
$ git clone https://github.com/Amaury/Dispak
```


### 2.3 Post-install

Once Dispak is installed, you can add an alias in your `~/.bashrc` or `~/.bash_aliases` file:
```shell
alias dpk='/path/to/Dispak/dpk'
```

This alias is very useful, it allows you to simply type `dpk` from anywhere in a git repository tree.

More, if you are using Bash as your command-line shell, you can take advantage of the bundled automatic completion script.

First, ensure to have the package `bash-completion` installed on your computer:
```shell
# apt install bash-completion
```

After that, add this line to the file `~/.bash_completion`:
```shell
. /path/to/Dispak/dispak_completion.bash
```


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
1. In your Dispak configuration file (see [below](#35-configuration-file)), fill the database related variables (`CONF_DB_HOST`, `CONF_DB_PORT`, `CONF_DB_USER`, `CONF_DB_PWD`, `CONF_DB_MIGRATION_BASE`, `CONF_DB_MIGRATION_TABLE`).
2. In your project's repository, create a `etc/database/migrations` directory.
3. In this directory, you must create a file named `current` which will contain all your `ALTER` commands. You must commit this file.
4. When you create a new tag with `dpk pkg`, the `current` file will be renamed with the tag version number(`X.Y.Z`), and a new empty `current` file is created.
5. When you deploy a tag on a server (`dpk install` command), Dispak will check in the migration table which was the last migration executed; then it will process every migration files that are not already processed, in their creation order.

As you can see, there is no process for migration roll-back. The main reason is to keep the system simple, by only writing  `ALTER` commands in plain SQL (whereas other database migration tools are usually using code written in a more complex programming language).
If you need to roll-back easily, maybe you should spend more time on your testing/staging platform. Anyway, you can do database backups before migrations. The recommended way to do that is to add the execution of [Arkiv](https://github.com/Amaury/Arkiv) in a pre-install script.


### 3.2 Crontab installation

In your project's git repository, you can create an `etc/crontab` file. During install, Dispak will add the content of this file to the crontab of the user who is performing the installation. This operation is done every time you install a new tagged version, so you just have to keep your `etc/crontab` file up-to-date. The previous content is replaced by the new file's content.
Your `etc/crontab` file must contain a [cron](https://en.wikipedia.org/wiki/Cron)-compatible content, including scheduling information.

You can add other commands in the user's crontab. Dispak add the content of the `etc/crontab` file between markers.
So your crontab will end looking like that:
```shell
# your commands
* * * * * local_command1
* * * * * local_command2

# ┏━━━━━┥DISPAK CRONTAB START┝━━━┥/path/to/project/etc/crontab┝━━━━━┓
* * * * * dispak_command1
* * * * * dispak_command2
# ┗━━━━━┥DISPAK CRONTAB END┝━━━━━┥/path/to/project/etc/crontab┝━━━━━┛

# other commands
* * * * * local_command3
* * * * * local_command4
```


### 3.3 Pre/post scripts execution

Dispak can execute scripts before and after packaging (the action of creating a new tag), configuration and installation.

These scripts could be written in any language. Their return status must be equal to 0 (zero); any other value will make Dispak to abort its processing.

Dispak gives two parameters to these scripts:
1. The platform environment (`dev`, `test` or `prod`).
2. The tag version number. For pre/post-packaging scripts it is the number of the created tag; for pre/post-config and pre/post-install scripts it is the number of the installed tag.

Pre/post configuration and installation scripts get two additional parameters:
1. The old tag version number.
2. A character that describes the tag evolution: "+" if the new tag is more recent than the old one; "-" if the new tag is older then the one that was installed.
These two extra parameters are empty if the installation is done over a `master` branch install.

See all these variables in the [configuration file](#38-configuration-file): `CONF_PKG_SCRIPTS_PRE`, `CONF_PKG_SCRIPTS_POST`, `CONF_INSTALL_SCRIPTS_PRE`, `CONF_INSTALL_SCRIPTS_POST`


### 3.4 Files generation

Dispak can generate files when it is installing a new tag. Usually it is used for configuration files, but it could be used for any file that must be generated on-the-fly.

Like the pre/post scripts (see the previous section), these scripts could be written in any language, and any return value different than 0 (zero) will stop Dispak processing.

Generator scripts must be placed in the same directory than the generated files, and must have the same name with the `.gen` extension at the end.

Again like the pre/post scripts (see the previous section), the generator scripts receive two arguments:
1. The platform environment (`dev`, `test` or `prod`).
2. The tag version number. For pre/post-packing scripts it is the number of the created tag; for pre/post-install scripts it is the number of the installed tag.

Generator scripts are listed in the `CONF_INSTALL_GENERATE` variable of the [configuration file](#38-cconfiguration-file).


### 3.5 Static files, symlinks and Amazon S3

Dispak helps you to manage the static files of your web projects.

There is two (non-mutually exclusive) ways to manage these files: Using symlink, and copying files to Amazon S3.

#### Symbolink links
You can define a list of symbolic links in the [configuration file](#38-configuration-file). These links will be created during the tag installation process. In fact, you define the target of each link (usually a directory but it can be a file), and the directory where these links are giong to be created. The created links are named with the installed version's number.

Example: Let's say your configuration file contains this line:
```shell
CONF_INSTALL_SYMLINK["www/css"]="www/css"
```

Now, when the version `1.2.0` is installed, the following link will be created:
```shell
$ ls -l www/css/1.2.0
www/css/1.2.0 -> .
```

Then you can adapt your templates:
```html
<link href="/css/{$conf.version}/style.css" rel="stylesheet">
```
(in this example, the `$conf.version` variable have been defined in the framework's configuration file, thanks to the [file generation](#34-files-generation) feature)

#### Amazon S3
It is also possible to define a bucket on Amazon S3 where your static files will be copied each time you create a *stable* version (or even for *unstable* version if you defined the `CONF_PKG_S3_UNSTABLE` configuration variable). A subdirectory will be created, named as the tag version number, and all configured files will be copied there.

Then, you can adapt your templates (see previous section) to use the copied assets.


### 3.6 Javascript and CSS files concatenation and minification

Dispak can concatenate and minify Javascript and CSS files, using the [`minifier` program](https://www.npmjs.com/package/minifier) (see [Installation prerequisites](#21-prerequisites) above). The files are generated (concatenated and minified) during the packaging process.

In the [Dispak configuration file](#38-configuration-file), the `CONF_PKG_MINIFY` is an associative array. Each key is the path to the generated file, and the value is a space-separated list of paths to the files to concatenate and minify.

If a generated (concatenated and minified) file is version controlled, it is automatically committed after generation. Otherwise it is deleted after the packaging process.


### 3.7 Apache configuration

If you list your Apache configuration files in the [Dispak configuration file](#38-configuration-file), Dispak will check if they are already added in the system configuration. If not, Dispak will add the needed files in the Apache configuration tree (`/etc/apache2/sites-available` and `/etc/apache2/sites-enabled`).

See the `CONF_INSTALL_APACHE_FILES` variable in the [configuration file](#38-configuration-file).


### 3.8 Configuration file

In a git repository, you can create a `dispak.conf` or `etc/dispak.conf` file. Look at the [`dispak-example.conf`](https://github.com/Amaury/Dispak/blob/master/dispak-example.conf) example file in the Dispak source repository.

There is three kind of configuration variables:
- Single values. The variable is waiting for a single value or file path.
- List of values. The variable is waiting for a single shell string (the whole content is surrounded by quotes) which can contain many values, separated with space or carriage return characters.
- Associative arrays. The variable may have many keys, each one could be affected to a single value or to a list of values.

Here are the definable variables:
- **Main configuration**
  - `CONF_GIT_MAIN`: If the main branch or your repository is not 'master' (more and more repositories are switching to 'main'), you must define it here.
  - `CONF_PLATFORM`: IF you don't want Dispak to detect the platform, you can set what is the current environment (`dev`, `test` or `prod`).
  - `CONF_PLATFORMS`: This variable is also used to override the automatic detection of the platform. But here is an associative array that allows you to specify the platform type associated with each server (from the server names).
- **pkg rule**
  - `CONF_PKG_CHECK_URL`: You can ask Dispak to check the return status of the given URL before creating a new tag. This is convenient if you have a local page that show the result of your unit tests; if the HTTP status of this page is an error (not equal to 200), the tag is not created.
  - `CONF_PKG_SCRIPTS_PRE`: You can ask Dispak to execute a list of scripts before creating a new tag.
  - `CONF_PKG_SCRIPTS_POST`: You can ask Dispak to execute a list of scripts after creating a new tag. These scripts are not executed if there was an error during the process.
  - `CONF_PKG_MINIFY`: It is possible to concatenate many files into one Javacript or CSS file, and then to minify this file. The `CONF_PKG_MINIFY` variable is an associative array. For each entry, the key is the path to the generated file, and the value is the list of source files.
  - `CONF_PKG_S3_UNSTABLE`: Set this variable to 1 if you want to copy static files to Amazon S3 for stable *and* unstable versions (not only for stable versions).
  - `CONF_PKG_S3`: If you want to copy static files to Amazon S3, use this variable. It is an associative array; for each entry, the key is the S3 bucket where the files will be copied, and the value is the path to the file or the directory that will be recursively copied. The files are copied in a sub-directory of the bucket's root, which name is the tag's version number.
- **install rule**
  - `CONF_INSTALL_SYMLINK`: Use this variable if you need to create symlinks when you install a new version. It is an associative array; the key is the path to the link's directory; the value is the path pointed by the link. The link will be created in its destination directory, and its name is the installed tag's version number.
  - `CONF_INSTALL_SCRIPTS_PRE`: Here is a list of scripts to execute before install.
  - `CONF_INSTALL_SCRIPTS_POST`: Here is a list of scripts to execute after install. The scripts are not executed if an error has occured during the install process.
  - `CONF_CONFIG_SCRIPTS_PRE`: Here is a list of scripts to execute before install (after pre-install scripts) or at the beginning of configuration (`dpk config` command).
  - `CONF_CONFIG_SCRIPTS_POST`: Here is a list of scripts to execute after install (before post-install scripts) or at the end of configuration (`dpk config` command). The scripts are not executed if an error has occured during the install process.
  - `CONF_INSTALL_APACHE_FILES`: This variable must contain a list of Apache configuration files. These files are listed in the system configuration (in `/etc/apache2/sites-available` and linked in `/etc/apache2/sites-enabled`) if they are not already.
  - `CONF_INSTALL_CHOWN`: Associative array. The keys are user logins, and the values are path to files and/or directories that must be changed of owner.
  - `CONF_INSTALL_CHMOD`: Associative array. The keys are a `chmod` file right (like `+x` or `644`), and the values are lists of files and/or directories that must be `chmod`'ed.
  - `CONF_INSTALL_GENERATE`: The variable must contain a list of files that must be *generated* after install. Each entry of the list must be the path to the *generated* file. For each one of them, a *generator* script must exist with the same name and a `.gen` extension. When a generator script is executed, everything coming out from its STDOUT will be written in the generated file.
- **Database management**
  - `CONF_DB_HOST`: Database host name.
  - `CONF_DB_PORT`: Database port number.
  - `CONF_DB_USER`: Database connection user name.
  - `CONF_DB_PWD`: Database connection password.
  - `CONF_DB_MIGRATION_BASE`: Name of the base which contains the migration table.
  - `CONF_DB_MIGRATION_TABLE`: Name of the table which contains migration information.

************************************************************************

## 4. Create your own rules

### 4.1 Why should you create your own rules?

Dispak's default rules are focused on source code management (create a tag, deploy a tag). Even the most advanced features (database migration, static files management) are dedicated to code deployment.

But Dispak can be used as a central entry point for managing all your command-line scripts. You can imagine an infinite list of additional capabilities:
- Manage users in a database.
- Manage daemons.
- Display data from a database.
- Generate configuration files or documentation.
- ...

Some examples are given in the [`example-rules/`](https://github.com/Amaury/Dispak/tree/master/example-rules) directory.


### 4.2 Where to put the rule?

Rules are simple Bash scripts. You can name the files as you want, as long as their names end with `.sh`.

You can put your rules files in two different places:
- In the `rules/` subdirectory of your Dispak installation tree. Then the rules will be shared with every other users who are using the same Dispak install. It's the preferred place to put general-usage rules.
- In the `etc/dispak-rules/` subdirectory of a git repository. Then the rules will be available to anybody working on this repository, but only when the current working directory in under this file tree. It's the dedicated place to put project-specific rules.


### 4.3 Simple example

You can take a look to the [`example-rules/minimal.sh`](https://github.com/Amaury/Dispak/blob/master/example-rules/minimal.sh) file:
```shell
#!/usr/bin/env bash

# "minimal" example rule for Dispak
# © 2017, Amaury Bouchard <amaury@amaury.net>

# Rule's name.
RULE_NAME="minimal"

# Show help for this rule.
rule_help_minimal() {
	echo "   dpk $(ansi bold)minimal$(ansi reset)"
	echo "       $(ansi dim)Minimal rule that displays the current user login and the current working directory.$(ansi reset)"
}

# Execution of the rule
rule_exec_minimal() {
	USER_LOGIN="$(id -un)"
	WORKING_DIR="$(pwd)"
	echo "Current user login:        $(ansi blue)$USER_LOGIN$(ansi reset)"
	echo "Current working directory: $(ansi yellow)$WORKING_DIR$(ansi reset)"
}
```

Here you can see the four minimal things in a Dispak rule:
1. The Bash [shebang](https://en.wikipedia.org/wiki/Shebang_(Unix)) on the first line (`#!/bin/sh`).
2. The `RULE_NAME` variable, which contains the name of the rule. This name must be unique.
3. The function used to display the rule's documentation. It must be called `rule_help_` followed by the rule's name. Please try to follow the same layout of other rules; use the `ansi` function (see [below](#49-provided-functions)) to change text color and decoration.
4. The function called when the rule is executed. It must be called `rule_exec_` followed by the rule's name.

As you can see, when you execute this command:
```shell
$ dpk minimal
```
you will see the current user login and the current working directory (the first one written in blue, the second one in yellow).


### 4.4 Parameters management

Dispak checks the options given on the command-line, to be sure that all mandatory parameters are given and no unknown parameter is provided.

In your rule, declare the list of mandatory parameters (separated with space or carriage return characters) in the `RULE_MANDATORY_PARAMS` variable, and the list of optional parameters in the `RULE_OPTIONAL_PARAMS` variable.

If an option can get a value, it will be available in `${DPK_OPT["option_name"]}`. If an option is used without a value on the command line, the value is then set to the option's name.


### 4.5 Documentation section

When you execute `dpk` or `dpk help`, rules are grouped under sections. You can specify your rule's section using the `RULE_SECTION` variable.

If you don't define the section, your rule will be shown under the `Default` section.

### 4.6 Configuration

If needed, your rules can be configured thanks to the `dispak.conf` file.

There is three different kind of configuration variables:
- Simple strings. These variables could be used (or not) without further ado.
- Arrays. These variables must be defined by including a declaration (`declare -a VAR_NAME`) in the rule's file.
- Associative arrays. These variables must also be defined (`declare -A VAR_NAME`) in the rule's file.


### 4.7 Advanced example

You can take a look to the [`example-rules/adduser.sh`](https://github.com/Amaury/Dispak/blob/master/example-rules/adduser.sh) file.

It's a rule that can be used to create a new user in database. It has two mandatory parameters (`app` and `name`) and one optional parameter (`admin`).

The parameters are checked and then a request is sent to a MySQL server. You can see the declaration of a configuration variable (associative array) and a private function.


### 4.8 Provided variables

Some variables are set by Dispak and avaiable to your rule:
- `DPK_ROOT`: Path to the root of the used Dispak installation.
- `GIT_REPO_PATH`: When Dispak is called from inside a Git repository, this variable contains the root path to this repository.
- `DPK_OPT`: Contains the options given on the command-line (see [above](#44-parameters-management)).


### 4.9 Provided functions

**`warn`**

Write a yellow "⚠" (warning sign) character, followed by your message.

Example:
```shell
warn "Something went wrong."
```

Your message should be written in yellow, but it's up to you (using the `ansi` function, see below).

**`abort`**

You *must* call this function when your rule failed. It displays a red "⛔" (no entry) character, followed by your message, followed by a red "ABORT" string. Then it exits with a status of 1 (which means an error).

Example:
```shell
abort "Something went really bad."
```

Your message should be written in red, but it's up to you (using the `ansi` function, see below).

**`trim`**

Remove spaces at the beginning and the end of a string.

Example:
```shell
VAR="$(trim "$VAR")"
```

**`filenamize`**

Convert a string that contains a path to a file, and return a string suitable as a file name. Replace slashes and spaces by dashes.

Example:
```shell
FILENAME="$(filenamize "$PATH_TO_FILE")"
```

**`ansi`**

Write [ANSI](https://en.wikipedia.org/wiki/ANSI_escape_code)-compatible statements.

Take at least one parameter:
- `reset`: Remove all previously defined text decoration.
- `bold`: Write text in bold.
- `dim`: Write faint text.
- `under`: Write underlined text.
- `black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`: Change the text color.
- `rev`: Write text in reverse video. Could take another parameter with the background color (see previous item for the list of colors).

Example:
```shell
echo "$(ansi red)Some colored text$(ansi reset), $(ansi bold)some important text$(ansi reset)"
echo "$(ansi bold)$(ansi under)Some very important text$(ansi reset)"
```

Don't forget to always end with a `reset`!

**`align_spaces`**

This function helps you to align texts. Call it with a text as first parameter, and it will display as many spaces as the string length. You can modify the length by given a second parameter like "+2" or "-3".

Example:
```shell
VAR=foobar
echo $VAR
align_spaces $VAR "+3"
echo "Something smart"
```

Result:
```
foobar
         Something smart
```

**`git_fetch`**

Fetch all tags and branches from distant git repository.

**`git_is_clean`**

Tell if the current Git repository is clean (all files are committed, no new file and no modified file).

**`git_get_current_branch`**

Return the name of the current branch.

**`git_get_branches`**

Return the list of branches.

**`git_get_current_tag`**

Return the name of the currently installed tag.

**`find_in_list`**

Tell if an item exists in a list.

**`check_aws`**

Check if the `aws-cli` program is installed. Abort if not.

**`check_dhbost`**

Check if the database host is defined and reachable (using `ping`). Abort if not.

**`check_sudo`**

Check if the user has sudo rights. Abort if not.

**`check_git`**

Check if we are in a git repository. Abort if not.

**`check_git_master`**

Check if we are on the master branch. Abort if not.

**`check_git_branch`**

Check if we are on a branch (not the master branch). Abort if not.

**`check_git_clean`**

Check if the git repository is clean (all files are committed, no new file and no modified file). If a "strict mode" parameter is given with a value of 1, it will abort if some uncommitted files exist; otherwise, it will ask the user.

**`check_git_pushed`**

Check if all committed files have been pushed to the remote git repository. Abort if not.

**`check_platform`**

Check the platform given as parameter (using `--platform` option), or detect the platform.

The current platform is set in the `${DPK_OPT["platform"]}` variable.

**`check_tag`**

Check if the tag given as a parameter already exists. Abort if not.

If no tag is given, fetch the last created tag and put it in the `${DPK_OPT["tag"]}` variable.

**`check_next_tag`**

Check if the tag given as a parameter is valid as the next tag. If not or if no tag is given, a list of valid tags is shown to the user, who must choose between them.

Then the tag is available in the `${DPK_OPT["tag"]}` variable.

