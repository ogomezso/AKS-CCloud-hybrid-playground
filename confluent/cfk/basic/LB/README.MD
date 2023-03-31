# Exposing Confluent Components through Load Balancer

## Inital Considerations

Adding the external access on Confluent Components will set up a `Kubernetes Load Balancer Resource` that will expose the existing headless service created on top of each one of the pods on the statefulset of the component.

This will give you a public IP at cluster level but due internal product requisites you will need to provide the domain used to expose that IP too.

## Control Center

As Control Center is a web based UI even on this basic setup we will be setting up basic authentication based on static user password configured on a secret.
