# Common — shared SpenDrop contracts

Platform-neutral definitions that **every** SpenDrop client (iOS, Web, future Android) and the Supabase schema follow.
This is not shared source code — Swift and TypeScript can't share it — but shared *contracts* that each platform
implements and **tests against**.

| Folder | Contents | Consumed by |
|---|---|---|
| `Constants/` | payment channels, categories, money-movement kinds, account types, split methods, currencies (JSON, with the exact raw values stored by iOS and the database) | Web `tests/domain/common-contract.test.ts`; database CHECK constraints |
| `DataModels/` | the record model every client stores and syncs | `Docs/Data-Model.md`, Supabase migrations |
| `BusinessRules/` | split calculation, balances & settlements, funding account vs channel, money rules + **JSON test vectors** | Web tests run every vector; iOS can adopt the same files |
| `Validation/` | input limits (money, text, dates) | all clients, database constraints |
| `Design/` | design tokens: colours (light/dark), surfaces, radii, typography, navigation | Web `globals.css`; iOS uses the system equivalents |

Rule of thumb: if a value is stored in the database or affects money, it belongs here first.
