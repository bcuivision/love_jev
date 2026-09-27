import { EnvHttpProxyAgent, setGlobalDispatcher } from "undici";

// Honor the operator's proxy while preserving TLS verification and NO_PROXY.
if (process.env.HTTPS_PROXY || process.env.HTTP_PROXY || process.env.https_proxy || process.env.http_proxy) {
  setGlobalDispatcher(new EnvHttpProxyAgent());
}
