# Compilers

We need to re-structurize how query suppliers work.
Currently you can define multiple suppliers, each say to which shell they are attributed too.
We want to change it from that to a table. meaning a supplier contains a mapping of shell to command.
If a shell has no command, we leave it out.
Vdir is capable of knowing the user default shell. It first tries to run the command with that shell.
If there is no value, it goes through each shell definition and sees whether its in the path until one matches, then it uses that one.
For that it uses the default shell.
Vdir has internal code to determine what syntax you need for a given command to execute it with the shell, and what the syntax is to define whethers something is in the path for a given name.

Write another markdown file which proposes syntax changes for the new support.

New feature is the pre-compiler. When defining a supplier, we always assume we use a compiler, unless we define --raw before.
A compiler has a name and can transform an arbitrary command into a map of shell to command. An example might be a compiler which is called 'ripgrep',
then when saying 'ripgrep <pattern>' it makes a table of shell to command, and for nu f.e. it transforms it into 'ripgrep -l <pattern> (pwd)'.
Compilers are defined in the vdir compiler file. Its a plaintext file that takes paths. It can also just take the command name if its in the path. It accepts windows exe's,
linux binaries, shims, shell files like .sh, .nu and .ps1, (again we know how to execute these already).
They can be invoked with '<compiler_container> list', which returns a linebreak seperated stream of compiler names,
and '<compiler_container> run <command>'.
