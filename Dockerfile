FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
WORKDIR /app
EXPOSE 8080
EXPOSE 8443

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG CODEARTIFACT_TOKEN
ENV CODEARTIFACT_TOKEN=$CODEARTIFACT_TOKEN
WORKDIR /src

COPY ["Aperture.Entitlements.Api/Aperture.Entitlements.Api.csproj", "Aperture.Entitlements.Api/"]
COPY ["Aperture.Entitlements.Contracts/Aperture.Entitlements.Contracts.csproj", "Aperture.Entitlements.Contracts/"]
COPY ["Aperture.Entitlements.Domain/Aperture.Entitlements.Domain.csproj", "Aperture.Entitlements.Domain/"]
COPY ["Aperture.Entitlements.Infrastructure/Aperture.Entitlements.Infrastructure.csproj", "Aperture.Entitlements.Infrastructure/"]
COPY ["Directory.Build.props", "."]
COPY ["Directory.Packages.props", "."]
COPY ["nuget.config", "."]

RUN dotnet restore "Aperture.Entitlements.Api/Aperture.Entitlements.Api.csproj"

COPY . .

RUN dotnet build "Aperture.Entitlements.Api/Aperture.Entitlements.Api.csproj" -c Release --no-restore -o /app/build

FROM build AS publish
RUN dotnet publish "Aperture.Entitlements.Api/Aperture.Entitlements.Api.csproj" -c Release --no-restore -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .

ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production
ENV DOTNET_RUNNING_IN_CONTAINER=true

ENTRYPOINT ["dotnet", "Aperture.Entitlements.Api.dll"]
