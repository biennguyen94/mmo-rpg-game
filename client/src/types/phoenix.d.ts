// Khai báo tối thiểu cho client JS của Phoenix (phoenix.mjs, phục vụ ở /vendor/phoenix.mjs qua
// import map trong index.html). Chỉ phần client dùng.
declare module "phoenix" {
  export class Push {
    receive(status: string, callback: (response: any) => void): Push;
  }

  export class Channel {
    join(timeout?: number): Push;
    leave(timeout?: number): Push;
    push(event: string, payload: object, timeout?: number): Push;
    on(event: string, callback: (payload: any) => void): number;
    onClose(callback: (payload?: any) => void): void;
    onError(callback: (reason?: any) => void): void;
  }

  export interface SocketOptions {
    params?: object | (() => object);
    reconnectAfterMs?: (tries: number) => number;
    rejoinAfterMs?: (tries: number) => number;
    heartbeatIntervalMs?: number;
    timeout?: number;
  }

  export class Socket {
    constructor(endPoint: string, opts?: SocketOptions);
    connect(): void;
    disconnect(callback?: () => void, code?: number, reason?: string): void;
    channel(topic: string, params?: object): Channel;
    onOpen(callback: () => void): string;
    onClose(callback: (event: any) => void): string;
    onError(callback: (error: any) => void): string;
    isConnected(): boolean;
  }
}
