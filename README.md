# NestJS ChangeLog

NestJS ChangeLog is a change tracker for NestJS. It is similar to [PaperTrail](https://github.com/paper-trail-gem/paper_trail) in that it hooks into entity events and saves the changes. It stores a ChangeLog that you can view or even revert to previous versions of a tracked entity.

## Getting Started

First, install the package using the link to a [release] tarball:

```bash
npm install "https://github.com/porterville-citrus-inc/nestjs-changelog/archive/refs/tags/nestjs-changelog-1.0.22.tgz"
```

Wrap your typeorm `ConnectionOptions` with our helper function that adds the necessary entity and subscriber.

```typescript
import { addChangeDetectionToConnection } from 'nestjs-changelog';
const TypeOrmConfig = addChangeDetectionToConnection({
    type: 'postgres',
    // ...
    // the rest of your regular typeorm config
    // ...
});
``` 

Add the `Change` entity to typeorm's `ormconfig.json` so that you can generate a migration for the new entity.

```json
{
    "entities": [
        "src/database/models/**/*.entity.ts",
        "node_modules/nestjs-changelog/dist/change.entity.js"
    ],
}
```

Generate the new migration

```bash
# generate it
npx ts-node -r tsconfig-paths/register node_modules/.bin/typeorm migration:generate -n add_nestjs_changelog
# run it
npx ts-node -r tsconfig-paths/register node_modules/.bin/typeorm migration:run
```

Finally, add the module to your `AppModule`

```typescript
import { ChangeModule } from 'nestjs-changelog';

@Module({
    imports: [
        TypeOrmModule.forRoot(TypeOrmConfig),
        ChangeModule.register({
            // this tells the change logger how to turn a user into a display name
            userToDisplayName: (user: any) => `${user.firstName} ${user.lastName}`
        }),
        // your other modules imports...
    ]
})
```

[release]: https://github.com/porterville-citrus-inc/nestjs-changelog/releases

## Tracking Changes

Now all you need to do to start tracking changes is pick an entity to track changes on and decorate it with the `@TrackChanges` decorator, for example:

```typescript
@Entity()
@TrackChanges()
export class MyTrackedEntity extends BaseEntity {
    // ...
}
```

Any change that goes through typeorm's lifecycle hooks in subscribers will now be tracked. Each change will create a `Change` record in the database.

There are some options you can pass to `@TrackChanges`

```typescript
/* only the attributes listed will trigger the creation of a change record,
   by default all attributes are watched */
only?: string[],

/* the attributes listed in `except` will not trigger the creation of a
   change record if only they are changed */
except?: string[],

/* allows you to choose whether to ignore timestamps like created at,
   updated at, and deleted at. By default, timestamps are ignored, set this
   to false to track changes to timestamps */
ignoresTimestamps?: boolean,
```

## Retrieving the ChangeLog

You can retrieve change records for a tracked entity by using the `ChangeRepository`'s `changeLogQuery` method. We return a `SelectQueryBuilder<Change>` from this method so that you can chain any additional methods you would like onto it, for example pagination.

```typescript
const trackedEntity = await this.myTrackedEntityRepository.findOne(id);
const allChanges = await this.changeRepository
	.changeLogQuery(trackedEntity)
	.getMany();
```

## Reverting a Change

You can revert any change like so:

```typescript
const change = await this.changeRepository.findOne(changeId);
await this.changeRepository.revert(change);
```

## Working with `Change`

You can preview what kind of entity reverting a change will generate. This would be useful for displaying to the user what reverting will do, before asking the user to confirm.

```typescript
const entity = await this.changeRepository.retreiveEntityBeforeChange(change)
```

You can traverse the ChangeLog

```typescript
// get the most recent change
const lastChange = await this.changeRepository.lastChange(entity); 

// get the oldest change.
const firstChange = await this.changeRepository.firstChange(entity); 

// get the next change (if any)
const nextChange = await this.changeRepository.next(change);

// get the previous change (if any)
const previousChange = await this.changeRepository.previous(change);
```

## Caveats and Limitations

### Associations

Currently the tracking of associations is limited to tracking `@ManyToOne`
changes. We cannot track changes to `@ManyToMany` or `@OneToMany` without a
more complicated procedure. This may be in the works later, depending on
need.

### Database Decisions

This package was made with the focus of keeping a valid changelog regardless
of anything that happens. As a result of this a few design choices have been
made. The users identifying name is denormalized in the database (we do not
store a foreign key to the user) to the `whoDisplay` column. This is to
ensure that even if a user is deleted from the database, we are still able to
an identifying display name, as well as store their old id.

We also store the actual changes as a `json` blob as well. This is to ensure
that the changes at the time are captured, regardless of how the database
schema looks.

### TypeORM API

TypeORM has a few eccentricities around which events can be monitored and
which can't, that users must keep in mind. Since `nestjs-changelog` is based
around detecting when an entity has changed, there are a few things to be
aware of. Typeorm has methods of inserting, updating and deleting that talk
directly with the database. These methods are `.delete`, `.update`, and
`insert` on repository and entity manager. Below is a demonstration of what
works and doesn't work in terms of automatic creation of `Change` entries.

```typescript
let entity = new SomeEntity();
await entity.save(); // works
await repository.save(entity); // works
await repository.insert({name: 'name'}); // does NOT cause a change to be created

await repository.save(entity); // works
await connection.manager.save(entity); // works
await entity.save(); // works
await repository.update(entity.id, {name: 'name'}); // does NOT cause a change to be created

await repository.remove(entity); // works
await connection.manager.remove(entity); // works
await entity.remove(); // works
await repository.delete(entity); // does NOT cause a change to be created

// using the query builder creates a direct sql query that does NOT trigger typeorm
await repository
  .createQueryBuilder()
  .anything()
```

As a workaround, if you still want to create change entries while utilizing
the query builder or direct database calls, you can use the
`changeRepository.createDatabaseEntry` method.

```typescript
// example of manually creating a change record because we are working with the direct db methods
// .insert
const insertResult = await connection.manager.insert(SomeEntity, { name: 'name' });
const entity = await connection.manager.findOne(SomeEntity, insertResult.identifiers[0].id);
// manually create an entry
await changeRepository.createChangeEntry(entity, ChangeAction.CREATE);

// .update
const entityBefore = await connection.manager.findOne(SomeEntity, 1);
await connection.manager.update(SomeEntity, { id: entityBefore.id }, { name: 'name' });
const entityAfter = await connection.manager.findOne(SomeEntity, entityBefore.id);
// manually create an entry
await changeRepository.createChangeEntry(entityAfter, ChangeAction.UPDATE, entityBefore);

// .delete
const entity = await connection.manager.findOne(SomeEntity, 1);
await connection.manager.delete(SomeEntity, { id: 1 });
// manually create an entry
await changeRepository.createChangeEntry(entity, ChangeAction.DELETE);
```

## Creating a new release

This package is intended for use directly from Github, using NPM's ability to
add a dependency from a given URL. To create a new release for use this way, use
one of the included NPM scripts.

Note: this requires the `gh` CLI installed and authenticated. You will also need
to configure the default remote repo: `gh repo set-default`

To release incrementing the version:

```sh
npm run release --next-ver=minor # Or any string accepted by `npm version`.
```

Shortcut to release incrementing the patch version:

```sh
npm run rel:patch
```

To release without incrementing the version (useful when testing):

```sh
npm run release
```
