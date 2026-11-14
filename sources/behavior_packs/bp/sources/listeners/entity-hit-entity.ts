import { EntityHitEntityAfterEvent, world } from '@minecraft/server';

world.afterEvents.entityHitEntity.subscribe(({ damagingEntity, hitEntity }: EntityHitEntityAfterEvent) => {
  world.sendMessage(`${damagingEntity.typeId} hit ${hitEntity.typeId}`);
});
