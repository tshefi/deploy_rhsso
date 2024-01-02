# deploy_rhsso
Automate deployment of RH SSH on an OCP cluster

While testing Terraform RHCS IDP config, I had to test an OpenID OCP IDP.
I figured why not install RH SSO on top of OCP cluster and then use TF RHCS IDP openid config,
to configure RH SSO as the OCP user identity provider.

This would seem easy to do, alas we must first install the RH SSO operator,
only then use it to create the needed keycloak resources before I could push them via TF to OCP. 

Installing an operator is a bit tricky; it may involve the need for time delay till everything installs.
We can't use OCP templates as these are available or can be added assuming the operator is already present.

We can't use a helm charts to deploy RH SSO, as current RH doesn't support it.

Ended up bashing my way around the timing issue, also helped me bypass the parameter issues I hit. Again we can't reuse or create OCP based templates which use parameters in yaml files as the operator isn't installed just yet.
