# jsonrpc
- `request`: jsonrpc, method, params, id
- `result`: jsonrpc,result, id
- `notify`: jsonrpc, method, Option<params>
- `error`: jsonrpc, error(code, message), id

### client
```ts
export class JsonRpcClient {
        constructor();
        on<T>(fn:function<T>(v:T));
    }
}
```