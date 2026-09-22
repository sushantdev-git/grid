/// Enumeration of BitChat terminal slash command types.
enum ChatCommandType {
  privateMessage,
  who,
  slap,
  ping,
  trace,
  stealth,
  join,
  clear,
  panic,
  nick,
  phone,
  help,
  unknown,
}

/// Metadata description for slash command autocompletion suggestions.
class CommandSuggestion {
  final String command;
  final String syntax;
  final String description;

  const CommandSuggestion({
    required this.command,
    required this.syntax,
    required this.description,
  });
}

/// Parser and structured representation of BitChat slash commands.
class ChatCommand {
  final ChatCommandType type;
  final String? target;
  final String? argument;
  final String rawInput;
  final String? errorMessage;

  const ChatCommand({
    required this.type,
    this.target,
    this.argument,
    required this.rawInput,
    this.errorMessage,
  });

  /// Whether a given input string begins with the slash command prefix.
  static bool isCommand(String text) => text.trim().startsWith('/');

  /// Complete list of supported BitChat commands with autocompletion descriptions.
  static const List<CommandSuggestion> availableSuggestions = [
    CommandSuggestion(
      command: '/msg',
      syntax: '/msg <peerId> <message>',
      description: 'Send an end-to-end encrypted direct message',
    ),
    CommandSuggestion(
      command: '/who',
      syntax: '/who',
      description: 'List all discovered peers and radio signal strengths',
    ),
    CommandSuggestion(
      command: '/slap',
      syntax: '/slap <peerId>',
      description: 'Slap a peer with a large trout',
    ),
    CommandSuggestion(
      command: '/ping',
      syntax: '/ping <peerId>',
      description: 'Send a diagnostic ping to test link latency',
    ),
    CommandSuggestion(
      command: '/trace',
      syntax: '/trace <peerId>',
      description: 'Run an active diagnostic traceroute probe (hops & RTT)',
    ),
    CommandSuggestion(
      command: '/stealth',
      syntax: '/stealth <on|off>',
      description: 'Toggle stealth relay mode (mask identity in mesh traces)',
    ),
    CommandSuggestion(
      command: '/join',
      syntax: '/join <#channel>',
      description: 'Join a public or geohash location channel (e.g. #9q8yy)',
    ),
    CommandSuggestion(
      command: '/clear',
      syntax: '/clear',
      description: 'Clear the current conversation timeline',
    ),
    CommandSuggestion(
      command: '/panic',
      syntax: '/panic',
      description: 'Instantly zeroize keys and wipe all in-memory data',
    ),
    CommandSuggestion(
      command: '/nick',
      syntax: '/nick <name>',
      description: 'Change your display nickname (2–20 chars)',
    ),
    CommandSuggestion(
      command: '/phone',
      syntax: '/phone <number>',
      description: 'Set your phone number for peer discovery (/phone clear to remove)',
    ),
    CommandSuggestion(
      command: '/help',
      syntax: '/help',
      description: 'Display all available commands',
    ),
  ];

  /// Filters autocomplete suggestions based on the user's current [query].
  static List<CommandSuggestion> getSuggestions(String query) {
    final clean = query.trim().toLowerCase();
    if (!clean.startsWith('/')) return [];
    return availableSuggestions
        .where((s) => s.command.toLowerCase().startsWith(clean))
        .toList();
  }

  /// Parses a raw user string into a structured [ChatCommand].
  static ChatCommand parse(String input) {
    final trimmed = input.trim();
    if (!trimmed.startsWith('/')) {
      return ChatCommand(
        type: ChatCommandType.unknown,
        rawInput: input,
        errorMessage: 'Not a slash command',
      );
    }

    final parts = trimmed.split(RegExp(r'\s+'));
    final cmd = parts[0].toLowerCase();

    switch (cmd) {
      case '/msg':
        if (parts.length < 3) {
          return ChatCommand(
            type: ChatCommandType.privateMessage,
            rawInput: input,
            errorMessage: 'Usage: /msg <peerId> <message>',
          );
        }
        final target = parts[1];
        final message = parts.sublist(2).join(' ');
        return ChatCommand(
          type: ChatCommandType.privateMessage,
          target: target,
          argument: message,
          rawInput: input,
        );

      case '/who':
        return ChatCommand(
          type: ChatCommandType.who,
          rawInput: input,
        );

      case '/slap':
        if (parts.length < 2) {
          return ChatCommand(
            type: ChatCommandType.slap,
            rawInput: input,
            errorMessage: 'Usage: /slap <peerId>',
          );
        }
        return ChatCommand(
          type: ChatCommandType.slap,
          target: parts[1],
          rawInput: input,
        );

      case '/ping':
        if (parts.length < 2) {
          return ChatCommand(
            type: ChatCommandType.ping,
            rawInput: input,
            errorMessage: 'Usage: /ping <peerId>',
          );
        }
        return ChatCommand(
          type: ChatCommandType.ping,
          target: parts[1],
          rawInput: input,
        );

      case '/trace':
        if (parts.length < 2) {
          return ChatCommand(
            type: ChatCommandType.trace,
            rawInput: input,
            errorMessage: 'Usage: /trace <peerId>',
          );
        }
        return ChatCommand(
          type: ChatCommandType.trace,
          target: parts[1],
          rawInput: input,
        );

      case '/stealth':
        if (parts.length < 2) {
          return ChatCommand(
            type: ChatCommandType.stealth,
            rawInput: input,
            errorMessage: 'Usage: /stealth <on|off>',
          );
        }
        return ChatCommand(
          type: ChatCommandType.stealth,
          argument: parts[1].toLowerCase(),
          rawInput: input,
        );

      case '/join':
        if (parts.length < 2) {
          return ChatCommand(
            type: ChatCommandType.join,
            rawInput: input,
            errorMessage: 'Usage: /join <#channel>',
          );
        }
        var channel = parts[1];
        if (!channel.startsWith('#')) {
          channel = '#$channel';
        }
        return ChatCommand(
          type: ChatCommandType.join,
          target: channel,
          rawInput: input,
        );

      case '/clear':
        return ChatCommand(
          type: ChatCommandType.clear,
          rawInput: input,
        );

      case '/panic':
        return ChatCommand(
          type: ChatCommandType.panic,
          rawInput: input,
        );

      case '/nick':
        if (parts.length < 2) {
          return ChatCommand(
            type: ChatCommandType.nick,
            rawInput: input,
            errorMessage: 'Usage: /nick <name>',
          );
        }
        return ChatCommand(
          type: ChatCommandType.nick,
          argument: parts.sublist(1).join(' '),
          rawInput: input,
        );

      case '/phone':
        if (parts.length < 2) {
          return ChatCommand(
            type: ChatCommandType.phone,
            rawInput: input,
            errorMessage: 'Usage: /phone <number>  or  /phone clear',
          );
        }
        final phoneArg = parts.sublist(1).join(' ');
        return ChatCommand(
          type: ChatCommandType.phone,
          argument: phoneArg.toLowerCase() == 'clear' ? '' : phoneArg,
          rawInput: input,
        );

      case '/help':
        return ChatCommand(
          type: ChatCommandType.help,
          rawInput: input,
        );

      default:
        return ChatCommand(
          type: ChatCommandType.unknown,
          rawInput: input,
          errorMessage: 'Unknown command "$cmd". Type /help for available commands.',
        );
    }
  }
}
