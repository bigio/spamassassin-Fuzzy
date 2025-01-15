# spamassassin-Fuzzy

This SpamAssassin plugin utilizes fuzzy signature detection to identify spam messages, even when they contain slight variations or attempts to obfuscate content.

## Installation

The plugin requires the following Perl modules:
- Digest::ssdeep
- JSON (not used by SpamAssassin plugin)
- List::Util
- Redis
- Text::WagnerFischer

## Usage

Copy the Fuzzy.* files under /etc/mail/spamassassin and configure Fuzzy.cf with your Redis server
