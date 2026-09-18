using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Aperture.Entitlements.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "entitlement");

            migrationBuilder.CreateTable(
                name: "app_role",
                schema: "entitlement",
                columns: table => new
                {
                    role_id = table.Column<Guid>(type: "uuid", nullable: false),
                    role_key = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    description = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                    status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_app_role", x => x.role_id);
                });

            migrationBuilder.CreateTable(
                name: "app_user",
                schema: "entitlement",
                columns: table => new
                {
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    first_name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    last_name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    email = table.Column<string>(type: "character varying(320)", maxLength: 320, nullable: false),
                    status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    context_version = table.Column<long>(type: "bigint", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_app_user", x => x.user_id);
                });

            migrationBuilder.CreateTable(
                name: "entitlement_outbox",
                schema: "entitlement",
                columns: table => new
                {
                    event_id = table.Column<Guid>(type: "uuid", nullable: false),
                    event_type = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    payload_json = table.Column<string>(type: "jsonb", nullable: false),
                    occurred_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    published_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_entitlement_outbox", x => x.event_id);
                });

            migrationBuilder.CreateTable(
                name: "role_assignment",
                schema: "entitlement",
                columns: table => new
                {
                    assignment_id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    role_id = table.Column<Guid>(type: "uuid", nullable: false),
                    effective_from = table.Column<DateOnly>(type: "date", nullable: false),
                    effective_to = table.Column<DateOnly>(type: "date", nullable: true),
                    assigned_by = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    assigned_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    revoked_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    revoked_by = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_role_assignment", x => x.assignment_id);
                    table.ForeignKey(
                        name: "FK_role_assignment_app_role_role_id",
                        column: x => x.role_id,
                        principalSchema: "entitlement",
                        principalTable: "app_role",
                        principalColumn: "role_id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_role_assignment_app_user_user_id",
                        column: x => x.user_id,
                        principalSchema: "entitlement",
                        principalTable: "app_user",
                        principalColumn: "user_id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "uq_app_role_key",
                schema: "entitlement",
                table: "app_role",
                column: "role_key",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "uq_app_user_email",
                schema: "entitlement",
                table: "app_user",
                column: "email",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_entitlement_outbox_pending",
                schema: "entitlement",
                table: "entitlement_outbox",
                columns: new[] { "published_at", "occurred_at" });

            migrationBuilder.CreateIndex(
                name: "ix_role_assignment_lookup",
                schema: "entitlement",
                table: "role_assignment",
                columns: new[] { "user_id", "role_id", "effective_from" });

            migrationBuilder.CreateIndex(
                name: "IX_role_assignment_role_id",
                schema: "entitlement",
                table: "role_assignment",
                column: "role_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "entitlement_outbox",
                schema: "entitlement");

            migrationBuilder.DropTable(
                name: "role_assignment",
                schema: "entitlement");

            migrationBuilder.DropTable(
                name: "app_role",
                schema: "entitlement");

            migrationBuilder.DropTable(
                name: "app_user",
                schema: "entitlement");
        }
    }
}
