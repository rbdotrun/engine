declare module '*.css' {
  const content: Record<string, string>
  export default content
}

declare module '@rails/actioncable' {
  export function createConsumer(url?: string): Cable

  export interface Cable {
    subscriptions: Subscriptions
    disconnect(): void
  }

  export interface Subscriptions {
    create(channel: string | ChannelNameWithParams, mixin?: CreateMixin): Subscription
  }

  export interface ChannelNameWithParams {
    channel: string
    [key: string]: unknown
  }

  export interface CreateMixin {
    connected?(): void
    disconnected?(): void
    received?(data: unknown): void
    [key: string]: unknown
  }

  export interface Subscription {
    perform(action: string, data?: object): void
    unsubscribe(): void
  }
}
