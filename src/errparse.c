/*
 * try matching an lsdbus error from a Lua error
 * the form is '<NAME>[.<SUBNAME>...]|<MESSAGE>'
 *
 * there can be arbitrary strings (like the position of the error
 * "file.lua:33") before the actual D-Bus error name followed by the
 * '|'
 */

#include <string.h>
#include <regex.h>
#include <stdio.h>

static const char *pattern = "([a-zA-Z_][a-zA-Z0-9_]*(\\.[a-zA-Z_][a-zA-Z0-9_]*)+)[[:space:]]*\\|[[:space:]]*(.*)";
static regex_t regex;
static int regex_ready = 0;

int errparse_init(void)
{
	if (regcomp(&regex, pattern, REG_EXTENDED) != 0)
		return 1;

	regex_ready = 1;
	return 0;
}

void errparse_cleanup(void)
{
	if (regex_ready) {
		regfree(&regex);
		regex_ready = 0;
	}
}

/*
 * Parse error message using compiled regex, copy error name into
 * `name` (a buffer of `name_size` bytes) and return pointer to
 * message part in `errmsg`.
 * Return NULL if parsing fails or the name doesn't fit into `name`.
 */
const char* errparse(const char* errmsg, char* name, size_t name_size)
{
	regmatch_t matches[4]; /* 0: whole, 1: name, 2: subpart, 3: message */

	if (!regex_ready || errmsg == NULL)
		return NULL;

	/* search anywhere in the string */
	if (regexec(&regex, errmsg, 4, matches, 0) != 0)
		return NULL;

	/* copy error name. names longer than the valid D-Bus maximum
	 * are treated as unparseable */
	size_t n_len = matches[1].rm_eo - matches[1].rm_so;

	if (n_len >= name_size)
		return NULL;

	memcpy(name, errmsg + matches[1].rm_so, n_len);
	name[n_len] = '\0';

	/* return pointer into original string for the message part */
	return errmsg + matches[3].rm_so;
}
