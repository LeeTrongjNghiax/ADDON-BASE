## Your Commands Here (Example)
say World initialized! Pack loaded for the first time.
give @p your_namespace:custom_block 1
give @p your_namespace:custom_sword 1

## Initialization
### Add objective
scoreboard objectives add your_namespace:q.is_initialised dummy

### Mark as Initialized
scoreboard players set .World your_namespace:q.is_initialised 0
