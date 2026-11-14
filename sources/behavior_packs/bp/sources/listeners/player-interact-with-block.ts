import { PlayerInteractWithBlockAfterEvent, world } from '@minecraft/server';

world.beforeEvents.playerInteractWithBlock.subscribe(
  ({ block, itemStack, player }: PlayerInteractWithBlockAfterEvent) => {
    world.sendMessage(`${player.name} interacted with ${block.typeId} using ${itemStack?.typeId}`);
  },
);
