# @sandrox/levixel

React Native and Expo adapter for the Levixel shared-transition image and video viewer.

The package contains thin Expo Modules bridges plus packaged Levixel native artifacts. It does not compile or copy the native viewer source into the consuming application.

```tsx
<Levixel items={items} theme="dark">
  {items.map((item, index) => (
    <Levixel.Source key={item.id} index={index} style={styles.tile}>
      <Image source={{ uri: item.thumbnailUrl ?? item.posterUrl ?? item.url }} style={styles.image} />
    </Levixel.Source>
  ))}
</Levixel>
```

Android hosts must remain edge-to-edge for uninterrupted system-bar transitions.
