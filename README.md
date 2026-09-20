# discourse-provide-full-name-in-mentions

Adds a `data-full-name` attribute to `@mentions` in cooked posts, carrying the user's or
group's full name alongside the handle.

```html
<a class="mention" data-full-name="Ada Lovelace" href="/u/ada">@ada</a>
<a class="mention-group notify" data-full-name="The Engineers" href="/groups/engineers">@engineers</a>
```

Themes and components can then show a real name next to, or instead of, the handle without
an extra request.

## Requires names to be collected

Discourse defaults `full_name_requirement` to **hidden at signup**, meaning a stock site
never asks for a name. With nothing collecting names, every mention renders
`data-full-name=""` and the plugin has nothing to show.

Set `full_name_requirement` to required or optional at signup. The plugin adds an admin
dashboard warning when it is enabled on a site that collects no names.

## Keeping cooked posts in sync

The attribute is written when a post is baked, so it does not appear in posts that were
cooked earlier, and it would go stale when a name changes.

**User renames are handled automatically.** Core enqueues `Jobs::ChangeDisplayName` on
every name change; this plugin extends that job to refresh mentions and revision history
too.

**Everything else needs the sync task:**

```bash
rake provide_full_name_in_mentions:sync        # add or refresh
rake provide_full_name_in_mentions:sync[2]     # sleep 2s between batches
DRY_RUN=1 rake provide_full_name_in_mentions:sync
```

Run it after installing (to backfill existing posts), after disabling (to strip the
attribute), and after renaming a **group** — groups have no core rename hook, so they are
not covered automatically.

The task patches cooked HTML directly rather than rebaking, the same approach core takes
for username and display-name changes. It reads only posts that contain a mention, and
never writes a record that is already correct, so re-running it is cheap.

## Settings

| Setting | Default | |
| --- | --- | --- |
| `provide_full_name_in_mentions_enabled` | true | Turns the attribute on and off. |

## Development

See `.devcontainer/devcontainer.json`. It expects a Discourse core checkout as a sibling
directory named `discourse`, and this repo symlinked into `core/plugins/`.

```bash
bin/rspec plugins/discourse-provide-full-name-in-mentions/spec
```
