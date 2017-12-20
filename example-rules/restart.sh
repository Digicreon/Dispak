#!/bin/bash

# "restart" rule for Dispak
# © 2017, Amaury Bouchard <amaury@amaury.net>

# Rule's name.
RULE_NAME="restart"

# Rule's section (for documentation).
RULE_SECTION="System administration"

# Show help for this rule.
rule_help_restart() {
	echo "   dpk $(ansi bold)restart$(ansi reset)"
	echo "       $(ansi dim)Restart Apache and Memcache.$(ansi reset)"
	echo "       $(ansi yellow)⚠ Needs sudo rights$(ansi reset)"
}

# Execution of the rule
rule_exec_restart() {
	check_sudo
	echo "$(ansi bold)Restarting Memcache...$(ansi reset)"
	sudo service memcached restart
	echo "$(ansi bold)Restarting Apache...$(ansi reset)"
	sudo apache2ctl restart
}
