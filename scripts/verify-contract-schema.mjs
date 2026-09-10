import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url))
const schemaPath = path.join(scriptDirectory, '..', 'contract', 'open.schema.json')
const schema = JSON.parse(fs.readFileSync(schemaPath, 'utf8'))
const itemsSchema = schema.properties?.items
const mediaItemSchema = schema.$defs?.mediaItem

assert.equal(
  itemsSchema?.['x-levixel-uniqueBy'],
  'id',
  'The open contract must machine-declare id as its cross-item uniqueness key',
)
assert.match(
  itemsSchema?.$comment ?? '',
  /JSON Schema 2020-12 cannot compare one property across sibling array items/,
  'The schema must explain the standard validator boundary',
)
assert.ok(
  mediaItemSchema?.required?.includes('id') && mediaItemSchema?.properties?.id?.minLength === 1,
  'The uniqueness key must be a required, non-empty media item property',
)

assert.equal(schema.properties.actions['x-levixel-uniqueBy'], 'id')
assert.deepEqual(schema.$defs.action.required, ['id', 'label'])
assert.equal(schema.$defs.action.additionalProperties, false)
assert.equal('onPress' in schema.$defs.action.properties, false, 'Callbacks must not cross the native JSON bridge')

console.log(`Verified contract schema boundary: ${schemaPath}`)
