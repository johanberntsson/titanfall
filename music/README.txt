To convert from sid to prg and use in a game

> psid64 -n -o Armalyte.prg Armalyte.sid

Check the start address

> hexdump -n 2 -C Armalyte.prg

Check where the init and playback routines start
> sidplayfp -v Armalyte.sid

